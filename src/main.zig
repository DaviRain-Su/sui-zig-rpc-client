const std = @import("std");
const client = @import("sui_client_zig");
const cli = @import("./cli.zig");
const commands = @import("./commands.zig");
const tx_pipeline = @import("./tx_pipeline.zig");
const keystore = client.keystore;
const RpcRequest = client.rpc_client.RpcRequest;

const Allocator = std.mem.Allocator;
const default_sui_client_config_path = ".sui/sui_config/client.yaml";
const default_sui_keystore_path = ".sui/sui_config/sui.keystore";
var test_keystore_path_override: ?[]const u8 = null;
const RpcConfigError = error{InvalidRpcConfig};

fn printCliError(message: []const u8) u8 {
    std.fs.File.stderr().deprecatedWriter().print("{s}", .{message}) catch {};
    return 1;
}

fn printLastError(rpc: *client.SuiRpcClient) u8 {
    if (rpc.getLastError()) |rpc_error| {
        const writer = std.fs.File.stderr().deprecatedWriter();
        if (rpc_error.code) |code| {
            writer.print("error: request failed (code={})\n", .{code}) catch {};
        } else {
            writer.print("error: request failed\n", .{}) catch {};
        }
        writer.print("  message: {s}\n", .{rpc_error.message}) catch {};
        return 1;
    }

    std.fs.File.stderr().deprecatedWriter().print("error: request failed\n", .{}) catch {};
    return 1;
}

fn printUnhandledError(err: anytype) u8 {
    std.fs.File.stderr().deprecatedWriter().print("error: {s}\n", .{@errorName(err)}) catch {};
    return 1;
}

fn expandTildePath(allocator: Allocator, path: []const u8) !?[]const u8 {
    if (path.len == 0 or std.mem.eql(u8, path, "~")) return null;
    if (!std.mem.startsWith(u8, path, "~/")) {
        return try allocator.dupe(u8, path);
    }

    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);
    const expanded = try std.fs.path.join(allocator, &.{ home_dir, path[2..] });
    defer allocator.free(expanded);
    return try allocator.dupe(u8, expanded);
}

fn resolveRpcUrlFromConfig(allocator: Allocator) !?[]const u8 {
    const env_config_path = std.process.getEnvVarOwned(allocator, "SUI_CONFIG") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    const explicit_config_path = env_config_path != null;
    const env_or_default_config_path = env_config_path orelse try defaultSuiClientConfigPath(allocator);
    if (env_or_default_config_path == null) return null;
    const config_path = env_or_default_config_path.?;
    defer allocator.free(config_path);
    if (config_path.len == 0) {
        if (explicit_config_path) return RpcConfigError.InvalidRpcConfig;
        return null;
    }

    const resolved_path = try expandTildePath(allocator, config_path);
    if (resolved_path == null) {
        if (explicit_config_path) return RpcConfigError.InvalidRpcConfig;
        return null;
    }
    defer allocator.free(resolved_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, resolved_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            if (explicit_config_path) return RpcConfigError.InvalidRpcConfig;
            return null;
        },
        else => return RpcConfigError.InvalidRpcConfig,
    };
    defer allocator.free(contents);

    return try requireRpcUrlFromConfigContent(allocator, contents);
}

fn defaultSuiClientConfigPath(allocator: Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_sui_client_config_path });
}

fn defaultSuiKeystorePath(allocator: Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_sui_keystore_path });
}

fn syncKeystoreTestPathOverride() void {
    keystore.test_keystore_path_override = test_keystore_path_override;
}

fn resolveSuiKeystorePath(allocator: Allocator) !?[]const u8 {
    syncKeystoreTestPathOverride();
    return try keystore.resolveDefaultSuiKeystorePath(allocator);
}

fn parseSuiKeystoreKeyFromArray(
    allocator: Allocator,
    contents: []const u8,
    selector: ?[]const u8,
) !?[]const u8 {
    if (selector) |value| {
        if (value.len == 0) return try keystore.parseFirstKey(allocator, contents);
        return try keystore.parseKeyBySelector(allocator, contents, value);
    }
    return try keystore.parseFirstKey(allocator, contents);
}

fn parseFirstSuiKeystoreKey(allocator: Allocator, contents: []const u8) !?[]const u8 {
    return parseSuiKeystoreKeyFromArray(allocator, contents, null);
}

fn parseSuiKeystoreKeyBySelector(allocator: Allocator, contents: []const u8, selector: []const u8) !?[]const u8 {
    return parseSuiKeystoreKeyFromArray(allocator, contents, selector);
}

fn resolveDefaultSuiKeystoreSelectedKey(allocator: Allocator, selector: []const u8) !?[]const u8 {
    syncKeystoreTestPathOverride();
    return try keystore.resolveSelectedKeyFromDefaultKeystore(allocator, selector);
}

fn resolveDefaultSuiKeystoreFirstKey(allocator: Allocator) !?[]const u8 {
    syncKeystoreTestPathOverride();
    return try keystore.resolveFirstKeyFromDefaultKeystore(allocator);
}

const YamlLine = struct {
    indent: usize,
    key: []const u8,
    value: []const u8,
    has_dash: bool,
};

fn countLeadingWhitespace(line: []const u8) usize {
    var index: usize = 0;
    while (index < line.len and (line[index] == ' ' or line[index] == '\t')) {
        index += 1;
    }
    return index;
}

fn parseYamlLine(line: []const u8) ?YamlLine {
    const indent = countLeadingWhitespace(line);
    const trimmed = std.mem.trimLeft(u8, line[indent..], " \t");
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var has_dash = false;
    var content = trimmed;
    if (content[0] == '-') {
        has_dash = true;
        content = std.mem.trimLeft(u8, content[1..], " \t");
        if (content.len == 0) return null;
    }

    const colon_index = std.mem.indexOfScalar(u8, content, ':') orelse return null;
    const key = std.mem.trim(u8, content[0..colon_index], " \t");
    if (key.len == 0) return null;
    const value = parseYamlTrimmedValue(content[colon_index + 1 ..]);
    return YamlLine{
        .indent = indent,
        .key = key,
        .value = value,
        .has_dash = has_dash,
    };
}

fn parseYamlTrimmedValue(raw_value: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw_value, " \t\r");
    if (value.len == 0) return value;

    if (value[0] != '\'' and value[0] != '"') {
        var comment_index: ?usize = null;
        for (value, 0..) |ch, index| {
            if (ch != '#') continue;
            if (index == 0) continue;
            if (value[index - 1] != ' ' and value[index - 1] != '\t') continue;
            comment_index = index;
            break;
        }
        if (comment_index) |index| {
            value = std.mem.trimRight(u8, value[0..index], " \t");
        }
    }

    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
            value = value[1 .. value.len - 1];
        }
    }

    return std.mem.trim(u8, value, " \t\r");
}

fn parseYamlRpcUrl(allocator: Allocator, contents: []const u8) !?[]const u8 {
    var active_env: ?[]const u8 = null;
    var line_iterator = std.mem.splitScalar(u8, contents, '\n');
    while (line_iterator.next()) |line| {
        const parsed = parseYamlLine(line) orelse continue;
        if (std.mem.eql(u8, parsed.key, "active_env") and parsed.value.len > 0) {
            active_env = parsed.value;
        }
    }

    line_iterator = std.mem.splitScalar(u8, contents, '\n');
    var in_envs = false;
    var env_indent: usize = 0;
    var in_active_env = false;
    var first_url: ?[]const u8 = null;

    while (line_iterator.next()) |line| {
        const parsed = parseYamlLine(line) orelse continue;

        if (std.mem.eql(u8, parsed.key, "envs")) {
            in_envs = true;
            env_indent = parsed.indent;
            in_active_env = false;
            continue;
        }

        if (in_envs and parsed.indent <= env_indent) {
            return if (first_url) |value| try allocator.dupe(u8, value) else null;
        }

        if (!in_envs) {
            if (std.mem.eql(u8, parsed.key, "rpc") or
                std.mem.eql(u8, parsed.key, "url") or
                std.mem.eql(u8, parsed.key, "rpc_url") or
                std.mem.eql(u8, parsed.key, "json_rpc_url"))
            {
                const trimmed = std.mem.trim(u8, parsed.value, " \n\r\t");
                if (trimmed.len > 0) return try allocator.dupe(u8, trimmed);
            }
            continue;
        }

        if (parsed.indent == env_indent + 2 and parsed.has_dash) {
            if (std.mem.eql(u8, parsed.key, "alias")) {
                if (parsed.value.len > 0 and active_env != null and std.mem.eql(u8, parsed.value, active_env.?)) {
                    in_active_env = true;
                } else {
                    in_active_env = false;
                }
            } else {
                in_active_env = false;
            }
            continue;
        }

        if (parsed.indent <= env_indent + 1) continue;

        if (std.mem.eql(u8, parsed.key, "url") or std.mem.eql(u8, parsed.key, "rpc") or std.mem.eql(u8, parsed.key, "rpc_url") or std.mem.eql(u8, parsed.key, "json_rpc_url")) {
            const trimmed = std.mem.trim(u8, parsed.value, " \n\r\t");
            if (trimmed.len == 0) continue;
            if (in_active_env) return try allocator.dupe(u8, trimmed);
            if (first_url == null) first_url = trimmed;
            continue;
        }
    }

    return if (first_url) |value| try allocator.dupe(u8, value) else null;
}

fn parseRpcUrlFromConfigContent(allocator: Allocator, contents: []const u8) !?[]const u8 {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch {
        if (parseYamlRpcUrl(allocator, trimmed) catch null) |yaml_url| {
            if (yaml_url.len > 0) return yaml_url;
        }
        return try allocator.dupe(u8, trimmed);
    };
    defer parsed.deinit();

    if (parsed.value == .string and parsed.value.string.len > 0) {
        const value = std.mem.trim(u8, parsed.value.string, " \n\r\t");
        if (value.len == 0) return null;
        return try allocator.dupe(u8, value);
    }
    if (parsed.value == .object) {
        if (parsed.value.object.get("rpc_url")) |url_value| {
            if (url_value == .string and url_value.string.len > 0) {
                const value = std.mem.trim(u8, url_value.string, " \n\r\t");
                if (value.len > 0) return try allocator.dupe(u8, value);
            }
        }
        if (parsed.value.object.get("json_rpc_url")) |url_value| {
            if (url_value == .string and url_value.string.len > 0) {
                const value = std.mem.trim(u8, url_value.string, " \n\r\t");
                if (value.len > 0) return try allocator.dupe(u8, value);
            }
        }
    }

    return null;
}

fn requireRpcUrlFromConfigContent(allocator: Allocator, contents: []const u8) ![]const u8 {
    return try parseRpcUrlFromConfigContent(allocator, contents) orelse RpcConfigError.InvalidRpcConfig;
}

fn resolveDefaultRpcUrl(allocator: Allocator) !?[]const u8 {
    const rpc_env = std.process.getEnvVarOwned(allocator, "SUI_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (rpc_env) |rpc_url| allocator.free(rpc_url);

    const config_url = try resolveRpcUrlFromConfig(allocator);
    defer if (config_url) |value| allocator.free(value);

    if (try resolveDefaultRpcUrlFromUrls(allocator, rpc_env, config_url)) |url| {
        return url;
    }

    return null;
}

fn resolveDefaultRpcUrlFromUrls(
    allocator: Allocator,
    rpc_url_env: ?[]const u8,
    config_url: ?[]const u8,
) !?[]const u8 {
    if (rpc_url_env) |rpc_url| {
        const trimmed = std.mem.trim(u8, rpc_url, " \n\r\t");
        if (trimmed.len > 0) {
            return try allocator.dupe(u8, trimmed);
        }
    }

    if (config_url) |value| {
        const trimmed = std.mem.trim(u8, value, " \n\r\t");
        if (trimmed.len > 0) {
            return try allocator.dupe(u8, trimmed);
        }
    }

    return null;
}

fn applyKeystoreSignature(allocator: Allocator, parsed: *cli.ParsedArgs) !void {
    const hasExistingSignature = struct {
        fn call(signatures: []const []const u8, value: []const u8) bool {
            for (signatures) |signature| {
                if (std.mem.eql(u8, signature, value)) return true;
            }
            return false;
        }
    }.call;

    const requires_tx_bytes = switch (parsed.command) {
        .tx_send, .tx_payload => parsed.tx_bytes != null or cli.hasProgrammaticTxInput(parsed),
        else => false,
    };
    if (!requires_tx_bytes) {
        return;
    }

    if (cli.hasProgrammaticTxInput(parsed) and tx_pipeline.defaultProgrammaticAccountProviderFromArgs(parsed) != null) {
        return;
    }

    if (parsed.signers.items.len > 0) {
        for (parsed.signers.items) |selector| {
            if (selector.len == 0) continue;
            const selector_key = try resolveDefaultSuiKeystoreSelectedKey(allocator, selector) orelse return error.InvalidCli;
            if (hasExistingSignature(parsed.signatures.items, selector_key)) {
                allocator.free(selector_key);
                continue;
            }
            try parsed.signatures.append(allocator, selector_key);
            try parsed.owned_signatures.append(allocator, selector_key);
        }
        return;
    }

    if (!parsed.from_keystore) return;

    if (parsed.signatures.items.len > 0) return;

    const key = try resolveDefaultSuiKeystoreFirstKey(allocator) orelse return error.InvalidCli;
    try parsed.signatures.append(allocator, key);
    try parsed.owned_signatures.append(allocator, key);
}

fn keystoreAddressField(obj: std.json.ObjectMap) ?[]const u8 {
    if (obj.get("address")) |value| {
        if (value == .string and value.string.len > 0) return value.string;
    }
    if (obj.get("suiAddress")) |value| {
        if (value == .string and value.string.len > 0) return value.string;
    }
    return null;
}

fn resolveSuiKeystoreAddressFromKeystoreContents(
    allocator: Allocator,
    contents: []const u8,
    selector: []const u8,
) !?[]const u8 {
    return try keystore.resolveAddressFromKeystoreContents(allocator, contents, selector);
}

fn resolveSuiKeystoreAddressBySelector(
    allocator: Allocator,
    selector: []const u8,
) !?[]const u8 {
    syncKeystoreTestPathOverride();
    return try keystore.resolveAddressBySelector(allocator, selector);
}

fn resolveTxBuildSenderAddress(
    allocator: Allocator,
    selector: []const u8,
) !?[]const u8 {
    if (selector.len == 0) return null;
    if (std.mem.startsWith(u8, selector, "0x")) {
        return try allocator.dupe(u8, selector);
    }

    return try resolveSuiKeystoreAddressBySelector(allocator, selector);
}

fn applyTxBuildSenderFromKeystore(
    allocator: Allocator,
    parsed: *cli.ParsedArgs,
) !void {
    const resolve_sender = struct {
        fn call(alloc: Allocator, selector: []const u8) !?[]const u8 {
            return resolveTxBuildSenderAddress(alloc, selector);
        }
    }.call;

    if (parsed.tx_build_sender) |sender| {
        if (sender.len == 0) return;

        const resolved_sender = try resolve_sender(allocator, sender) orelse return error.InvalidCli;
        if (parsed.owned_tx_build_sender) |owned| allocator.free(owned);
        parsed.owned_tx_build_sender = resolved_sender;
        parsed.tx_build_sender = resolved_sender;
        return;
    }

    if (parsed.signers.items.len == 0) return;

    var has_resolver_input = false;
    for (parsed.signers.items) |selector| {
        has_resolver_input = true;
        const resolved_sender = try resolve_sender(allocator, selector) orelse continue;
        if (parsed.owned_tx_build_sender) |owned| allocator.free(owned);
        parsed.owned_tx_build_sender = resolved_sender;
        parsed.tx_build_sender = resolved_sender;
        return;
    }

    if (has_resolver_input) return error.InvalidCli;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parsed = parseArgs(allocator, if (args.len > 1) args[1..] else &[_][]const u8{}) catch |err| {
        if (err == error.InvalidCli or err == error.OutOfMemory) {
            _ = printCliError("error: invalid arguments\n");
            const stdout = std.fs.File.stdout().deprecatedWriter();
            try cli.printUsage(stdout);
            return;
        }
        std.debug.print("error: {s}\n", .{@errorName(err)});
        return;
    };
    defer parsed.deinit(allocator);

    if (!parsed.has_rpc_url) {
        const resolved_rpc_url = resolveDefaultRpcUrl(allocator) catch |err| switch (err) {
            RpcConfigError.InvalidRpcConfig => {
                _ = printCliError("error: invalid rpc config\n");
                return;
            },
            else => return err,
        };
        if (resolved_rpc_url) |rpc_url| {
            parsed.owned_rpc_url = rpc_url;
            parsed.rpc_url = rpc_url;
        }
    }

    if (parsed.show_usage and parsed.command == .help) {
        const stdout = std.fs.File.stdout().deprecatedWriter();
        try cli.printUsage(stdout);
        return;
    }

    syncKeystoreTestPathOverride();
    try applyKeystoreSignature(allocator, &parsed);

    var rpc = if (parsed.request_timeout_ms) |timeout_ms|
        try client.SuiRpcClient.initWithTimeout(allocator, parsed.rpc_url, timeout_ms)
    else
        try client.SuiRpcClient.init(allocator, parsed.rpc_url);
    defer rpc.deinit();

    const status = run(allocator, &rpc, &parsed) catch |err| switch (err) {
        error.InvalidCli => printCliError("error: invalid arguments\n"),
        error.UnresolvedMoveFunctionExecutionTemplate => printLastError(&rpc),
        error.Timeout => printCliError("error: timeout\n"),
        client.ClientError.HttpError => printLastError(&rpc),
        client.ClientError.RpcError => printLastError(&rpc),
        client.ClientError.InvalidResponse => printCliError("error: invalid rpc response\n"),
        else => printUnhandledError(err),
    };

    if (status != 0) std.process.exit(status);
}

fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !cli.ParsedArgs {
    return cli.parseCliArgs(allocator, argv);
}

fn run(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    parsed: *const cli.ParsedArgs,
) !u8 {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try commands.runCommand(allocator, rpc, parsed, stdout);
    return 0;
}

test "parseRpcUrlFromConfigContent parses JSON string value" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator, "\"https://example.com:443\" ");
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://example.com:443", rpc_url orelse "");
}

test "parseRpcUrlFromConfigContent parses object with rpc_url" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator, "{\"json_rpc_url\":\"https://fallback.example\",\"rpc_url\":\"https://primary.example\"} ");
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://primary.example", rpc_url orelse "");
}

test "parseRpcUrlFromConfigContent parses object with json_rpc_url fallback" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator, "{\"json_rpc_url\":\"https://fallback.example\"}");
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://fallback.example", rpc_url orelse "");
}

test "parseRpcUrlFromConfigContent uses json_rpc_url when rpc_url is blank" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(
        allocator,
        "{ \"rpc_url\": \"   \", \"json_rpc_url\": \"https://fallback.example\" }",
    );
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://fallback.example", rpc_url orelse "");
}

test "parseRpcUrlFromConfigContent parses plain text fallback" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator, "  https://raw.example \n");
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://raw.example", rpc_url orelse "");
}

test "parseRpcUrlFromConfigContent parses active_env Sui yaml config" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator,
        \\active_env: testnet
        \\envs:
        \\  - alias: devnet
        \\    rpc: https://devnet.example
        \\  - alias: testnet
        \\    url: https://testnet.example
    );
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://testnet.example", rpc_url.?);
}

test "requireRpcUrlFromConfigContent rejects blank config" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(RpcConfigError.InvalidRpcConfig, requireRpcUrlFromConfigContent(allocator, " \n\t "));
}

test "requireRpcUrlFromConfigContent rejects unsupported structured config" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(
        RpcConfigError.InvalidRpcConfig,
        requireRpcUrlFromConfigContent(allocator, "{\"active_env\":\"testnet\"}"),
    );
}

test "parseRpcUrlFromConfigContent parses fallback yaml url when active_env is absent" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator,
        \\envs:
        \\  - alias: devnet
        \\    rpc: https://devnet.example
        \\  - alias: mainnet
        \\    url: https://mainnet.example
    );
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("https://devnet.example", rpc_url.?);
}

test "parseFirstSuiKeystoreKey reads first key from json array" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const key = try parseFirstSuiKeystoreKey(allocator,
        \\["sk1", "sk2", "sk3"]
    );
    try testing.expect(key != null);
    defer allocator.free(key.?);
    try testing.expectEqualStrings("sk1", key.?);
}

test "parseFirstSuiKeystoreKey handles empty array" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const key = try parseFirstSuiKeystoreKey(allocator, "[]");
    try testing.expect(key == null);
}

test "parseFirstSuiKeystoreKey reads privateKey field from object entry" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const key = try parseFirstSuiKeystoreKey(allocator,
        \\[{"key":"alias","privateKey":"sk_obj"}]
    );
    try testing.expect(key != null);
    defer allocator.free(key.?);
    try testing.expectEqualStrings("sk_obj", key.?);
}

test "parseSuiKeystoreKeyBySelector selects by alias field" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const key = try parseSuiKeystoreKeyBySelector(
        allocator,
        "[{\"alias\":\"main\",\"privateKey\":\"alias_key\"},{\"alias\":\"dev\",\"privateKey\":\"dev_key\"}]",
        "dev",
    );
    try testing.expect(key != null);
    defer allocator.free(key.?);
    try testing.expectEqualStrings("dev_key", key.?);
}

test "parseSuiKeystoreKeyBySelector falls back when selector missing and returns null" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const key = try parseSuiKeystoreKeyBySelector(
        allocator,
        "[{\"alias\":\"main\",\"privateKey\":\"alias_key\"}]",
        "unknown",
    );
    try testing.expect(key == null);
}

test "resolveSuiKeystoreAddressFromKeystoreContents resolves alias to address" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const contents =
        \\[
        \\  {"alias":"main","privateKey":"sk1","address":"0xabc"},
        \\  {"alias":"dev","suiAddress":"0xdef","privateKey":"sk2"}
        \\]
    ;

    const resolved = try resolveSuiKeystoreAddressFromKeystoreContents(allocator, contents, "dev");
    defer if (resolved) |value| allocator.free(value);
    try testing.expect(resolved != null);
    try testing.expectEqualStrings("0xdef", resolved.?);
}

test "resolveSuiKeystoreAddressFromKeystoreContents requires indexable and addressable selector" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const contents =
        \\[{"alias":"noaddr","privateKey":"sk1"}]
    ;

    const missing = try resolveSuiKeystoreAddressFromKeystoreContents(allocator, contents, "0");
    try testing.expect(missing == null);
}

test "applyTxBuildSenderFromKeystore uses signer as sender when sender is omitted" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = cli.ParsedArgs{
        .command = .tx_build,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };
    defer parsed.deinit(allocator);

    try parsed.signers.append(allocator, "0xabc");

    try applyTxBuildSenderFromKeystore(allocator, &parsed);

    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
}

test "applyTxBuildSenderFromKeystore rejects signer selector without resolvable address" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_sender_noaddr_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"missing-address\",\"privateKey\":\"sig\",\"noAddressKey\":\"0xabc\"}]");

    var parsed = cli.ParsedArgs{
        .command = .tx_build,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };
    try parsed.signers.append(allocator, "missing-address");
    defer parsed.deinit(allocator);

    try testing.expectError(error.InvalidCli, applyTxBuildSenderFromKeystore(allocator, &parsed));
}

test "applyKeystoreSignature appends signature from --signer selector" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_signature_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};

    try file.writeAll("[{\"alias\":\"dev\",\"privateKey\":\"selector-key\",\"address\":\"0xabc\"}]");

    var parsed = cli.ParsedArgs{
        .command = .tx_send,
        .tx_bytes = "AAABBB",
    };
    try parsed.signers.append(allocator, "dev");
    defer parsed.deinit(allocator);

    try applyKeystoreSignature(allocator, &parsed);

    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("selector-key", parsed.signatures.items[0]);
}

test "applyKeystoreSignature deduplicates duplicate --signer selectors" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_signature_dup_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};

    try file.writeAll("[{\"alias\":\"dev\",\"privateKey\":\"dup-signature\",\"address\":\"0xabc\"}]");

    var parsed = cli.ParsedArgs{
        .command = .tx_send,
        .tx_bytes = "AAABBB",
    };
    try parsed.signers.append(allocator, "dev");
    try parsed.signers.append(allocator, "dev");
    defer parsed.deinit(allocator);

    try applyKeystoreSignature(allocator, &parsed);

    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("dup-signature", parsed.signatures.items[0]);
}

test "applyKeystoreSignature avoids duplicating existing signatures" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_signature_existing_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};

    try file.writeAll("[{\"alias\":\"dev\",\"privateKey\":\"dup-signature\",\"address\":\"0xabc\"}]");

    var parsed = cli.ParsedArgs{
        .command = .tx_send,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };
    try parsed.signatures.append(allocator, "dup-signature");
    try parsed.signers.append(allocator, "dev");
    defer parsed.deinit(allocator);

    try applyKeystoreSignature(allocator, &parsed);

    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("dup-signature", parsed.signatures.items[0]);
}

test "applyKeystoreSignature resolves sender/signature from file-backed signer selector with whitespace" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_ws_file_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);
    const selector_path = try std.fmt.allocPrint(allocator, "tmp_main_signer_ws_file_{d}.txt", .{std.time.milliTimestamp()});
    defer allocator.free(selector_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var keystore_file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer keystore_file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try keystore_file.writeAll("[{\"alias\":\"dev\",\"privateKey\":\"ws-signature\",\"address\":\"0xabc\"}]");

    var selector_file = try std.fs.cwd().createFile(selector_path, .{ .truncate = true });
    defer selector_file.close();
    defer _ = std.fs.cwd().deleteFile(selector_path) catch {};
    try selector_file.writeAll("  dev\n");

    const signer_arg = try std.fmt.allocPrint(allocator, "@{s}", .{selector_path});
    defer allocator.free(signer_arg);
    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "AAABBB",
        "--signer",
        signer_arg,
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try applyTxBuildSenderFromKeystore(allocator, &parsed);
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expect(parsed.tx_build_sender != null);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("ws-signature", parsed.signatures.items[0]);
}

test "runCommand tx_send uses --signer selector to set sender and signatures" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_sender_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};

    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };
    try args.signers.append(allocator, "builder");
    defer args.deinit(allocator);

    try applyTxBuildSenderFromKeystore(allocator, &args);
    try applyKeystoreSignature(allocator, &args);

    try testing.expect(args.tx_build_sender != null);
    try testing.expectEqualStrings("0xbuilder", args.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 0), args.signatures.items.len);
}

test "runCommand tx_build resolves signer selector without main-side sender rewrites" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_tx_build_sender_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_emit_tx_block = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
    };
    try args.signers.append(allocator, "builder");
    defer args.deinit(allocator);

    try testing.expect(args.tx_build_sender == null);

    syncKeystoreTestPathOverride();

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try commands.runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"sender\":\"0xbuilder\"") != null);
}

test "runCommand tx_send can execute with signer selector only" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_sender_run_cmd_payload_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--signer",
        "builder",
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try applyTxBuildSenderFromKeystore(allocator, &parsed);
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expect(parsed.tx_build_sender != null);
    try testing.expectEqualStrings("0xbuilder", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 0), parsed.signatures.items.len);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var params_text: ?[]const u8 = null;
    var method_text: ?[]const u8 = null;
    const MockContext = struct {
        params_text: *?[]const u8,
        method_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            ctx.method_text.* = try alloc.dupe(u8, req.method);
            return alloc.dupe(u8, "{\"result\":{\"executed\":true}}\n");
        }
    }.call;

    var mock_ctx = MockContext{
        .params_text = &params_text,
        .method_text = &method_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try commands.runCommand(allocator, &rpc, &parsed, output.writer(allocator));

    try testing.expect(params_text != null);
    try testing.expect(method_text != null);
    try testing.expectEqualStrings("sui_executeTransactionBlock", method_text.?);
    defer allocator.free(params_text.?);
    defer allocator.free(method_text.?);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);

    const signatures = payload.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-builder", signatures.items[0].string);
}

test "runCommand tx_send can execute with signer selector only through default-keystore provider" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_sender_run_cmd_provider_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--signer",
        "builder",
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    syncKeystoreTestPathOverride();
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expect(parsed.tx_build_sender == null);
    try testing.expectEqual(@as(usize, 0), parsed.signatures.items.len);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var params_text: ?[]const u8 = null;
    var method_text: ?[]const u8 = null;
    const MockContext = struct {
        params_text: *?[]const u8,
        method_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            ctx.method_text.* = try alloc.dupe(u8, req.method);
            return alloc.dupe(u8, "{\"result\":{\"executed\":true}}\n");
        }
    }.call;

    var mock_ctx = MockContext{
        .params_text = &params_text,
        .method_text = &method_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try commands.runCommand(allocator, &rpc, &parsed, output.writer(allocator));

    try testing.expect(params_text != null);
    try testing.expect(method_text != null);
    try testing.expectEqualStrings("sui_executeTransactionBlock", method_text.?);
    defer allocator.free(params_text.?);
    defer allocator.free(method_text.?);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);

    const signatures = payload.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-builder", signatures.items[0].string);
}

test "runCommand tx_payload resolves sender aliases through default-keystore provider without main-side sender rewrites" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_payload_sender_alias_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    const args = [_][]const u8{
        "tx",
        "payload",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--sender",
        "builder",
        "--signature",
        "sig-manual",
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    syncKeystoreTestPathOverride();
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expect(parsed.tx_build_sender != null);
    try testing.expectEqualStrings("builder", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-manual", parsed.signatures.items[0]);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try commands.runCommand(allocator, &rpc, &parsed, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expectEqual(@as(usize, 2), payload.value.array.items.len);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);

    const signatures = payload.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-manual", signatures.items[0].string);
}

test "applyKeystoreSignature skips programmatic inputs handled by default-keystore providers" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = cli.ParsedArgs{
        .command = .tx_send,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .from_keystore = true,
    };
    defer parsed.deinit(allocator);

    try parsed.signers.append(allocator, "builder");
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expectEqual(@as(usize, 0), parsed.signatures.items.len);
}

test "runCommand tx_payload can build from signer selector only" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_payload_run_cmd_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    const args = [_][]const u8{
        "tx",
        "payload",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--signer",
        "builder",
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try applyTxBuildSenderFromKeystore(allocator, &parsed);
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expect(parsed.tx_build_sender != null);
    try testing.expectEqualStrings("0xbuilder", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 0), parsed.signatures.items.len);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try commands.runCommand(allocator, &rpc, &parsed, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expectEqual(@as(usize, 2), payload.value.array.items.len);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);

    const signatures = payload.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-builder", signatures.items[0].string);
}

test "runCommand tx_simulate uses signer selector for sender" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_simulate_run_cmd_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    const args = [_][]const u8{
        "tx",
        "simulate",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--signer",
        "builder",
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try applyTxBuildSenderFromKeystore(allocator, &parsed);
    try applyKeystoreSignature(allocator, &parsed);

    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("builder", parsed.signers.items[0]);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var params_text: ?[]const u8 = null;
    var method_ok = false;
    const MockContext = struct {
        params_text: *?[]const u8,
        method_ok: *bool,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .params_text = &params_text,
        .method_ok = &method_ok,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try commands.runCommand(allocator, &rpc, &parsed, output.writer(allocator));

    try testing.expect(params_text != null);
    try testing.expect(method_ok);
    defer allocator.free(params_text.?);

    const params = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);
}

test "cli parse + helper resolution maps tx_send signer to sender and signature" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_main_keystore_sender_run_cmd_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = test_keystore_path_override;
    test_keystore_path_override = keystore_path;
    defer test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"privateKey\":\"sig-builder\",\"alias\":\"builder\",\"address\":\"0xbuilder\"}]");

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--args",
        "[\"0xabc\"]",
        "--signer",
        "builder",
    };
    var parsed = try cli.parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try applyTxBuildSenderFromKeystore(allocator, &parsed);
    try applyKeystoreSignature(allocator, &parsed);
    try testing.expect(parsed.tx_build_sender != null);
    try testing.expectEqualStrings("0xbuilder", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 0), parsed.signatures.items.len);
    try testing.expect(parsed.signers.items.len == 1);
}

test "listAccountEntriesFromContents returns invalid cli on non-array data" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, keystore.listAccountEntriesFromContents(allocator, "{}"));
}

test "parseRpcUrlFromConfigContent returns null for empty config" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator, "   \n\t");
    try testing.expect(rpc_url == null);
}

test "resolveDefaultRpcUrlFromUrls prefers SUI_RPC_URL over config" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try resolveDefaultRpcUrlFromUrls(
        allocator,
        "  https://rpc-from-env.com  ",
        "https://rpc-from-config.com",
    );
    defer if (rpc_url) |value| allocator.free(value);
    try testing.expect(rpc_url != null);
    try testing.expectEqualStrings("https://rpc-from-env.com", rpc_url.?);
}

test "resolveDefaultRpcUrlFromUrls trims and keeps config when env is blank" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try resolveDefaultRpcUrlFromUrls(
        allocator,
        "   \n",
        "  https://rpc-from-config.com  ",
    );
    defer if (rpc_url) |value| allocator.free(value);
    try testing.expect(rpc_url != null);
    try testing.expectEqualStrings("https://rpc-from-config.com", rpc_url.?);
}

test "resolveDefaultRpcUrlFromUrls returns null if no source provides url" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try resolveDefaultRpcUrlFromUrls(
        allocator,
        "   ",
        " \t ",
    );
    try testing.expect(rpc_url == null);
}

test "parseRpcUrlFromConfigContent falls back to raw text for invalid JSON" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_url = try parseRpcUrlFromConfigContent(allocator, "not-json");
    try testing.expect(rpc_url != null);
    defer allocator.free(rpc_url.?);

    try testing.expectEqualStrings("not-json", rpc_url.?);
}

test "expandTildePath returns null for bare tilde" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const resolved = try expandTildePath(allocator, "~");
    try testing.expect(resolved == null);
}

test "expandTildePath passes through non-tilde path" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const resolved = try expandTildePath(allocator, "relative/path.json");
    defer allocator.free(resolved.?);

    try testing.expect(resolved != null);
    try testing.expectEqualStrings("relative/path.json", resolved.?);
}

test "expandTildePath expands home shorthand when HOME is set" {
    const testing = std.testing;
    const home = std.process.getEnvVarOwned(std.testing.allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return,
    };
    defer std.testing.allocator.free(home);

    const resolved = try expandTildePath(std.testing.allocator, "~/config");
    try testing.expect(resolved != null);
    defer std.testing.allocator.free(resolved.?);

    try testing.expect(std.mem.endsWith(u8, resolved.?, "/config"));
}
