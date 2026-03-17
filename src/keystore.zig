const std = @import("std");
const tx_builder = @import("./tx_builder.zig");

pub const default_sui_keystore_path = ".sui/sui_config/sui.keystore";
pub var test_keystore_path_override: ?[]const u8 = null;

pub const SignerPreparation = struct {
    signer_selectors: []const []const u8 = &.{},
    from_keystore: bool = false,
    infer_sender_from_signers: bool = true,
};

pub const PreparedProgrammaticRequest = struct {
    request: tx_builder.ProgrammaticTxRequest,
    combined_signatures: std.ArrayListUnmanaged([]const u8) = .{},
    owned_signatures: std.ArrayListUnmanaged([]const u8) = .{},
    owned_sender: ?[]const u8 = null,

    pub fn deinit(self: *PreparedProgrammaticRequest, allocator: std.mem.Allocator) void {
        if (self.owned_sender) |value| allocator.free(value);
        for (self.owned_signatures.items) |value| allocator.free(value);
        self.combined_signatures.deinit(allocator);
        self.owned_signatures.deinit(allocator);
    }
};

fn expandTildePath(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
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

fn defaultSuiKeystorePath(allocator: std.mem.Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_sui_keystore_path });
}

pub fn resolveDefaultSuiKeystorePath(allocator: std.mem.Allocator) !?[]const u8 {
    if (test_keystore_path_override) |override_path| {
        if (override_path.len == 0) return null;
        return try allocator.dupe(u8, override_path);
    }

    const env_or_default_keystore_path = std.process.getEnvVarOwned(allocator, "SUI_KEYSTORE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try defaultSuiKeystorePath(allocator),
        else => return err,
    };
    if (env_or_default_keystore_path == null) return null;
    const keystore_path = env_or_default_keystore_path.?;
    defer allocator.free(keystore_path);
    if (keystore_path.len == 0) return null;

    return try expandTildePath(allocator, keystore_path);
}

fn parseKeyFromArray(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: ?[]const u8,
) !?[]const u8 {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .array) return null;
    const need_selector = if (selector) |value| value.len > 0 else false;
    const selector_index = if (selector) |value| std.fmt.parseInt(usize, value, 10) catch null else null;

    for (parsed.value.array.items, 0..) |entry, index| {
        if (selector_index) |target_index| {
            if (index != target_index) continue;
        }

        if (entry == .string) {
            const raw_key = entry.string;
            if (raw_key.len == 0) continue;
            if (!need_selector or selector_index != null or std.mem.eql(u8, raw_key, selector.?)) {
                return try allocator.dupe(u8, raw_key);
            }
            continue;
        }

        if (entry != .object) continue;
        const obj = entry.object;
        const candidate_key = blk: {
            if (stringField(obj, "privateKey")) |value| break :blk value;
            if (stringField(obj, "key")) |value| break :blk value;
            if (stringField(obj, "value")) |value| break :blk value;
            break :blk null;
        };
        if (candidate_key == null or candidate_key.?.len == 0) continue;

        if (!need_selector or selector_index != null or std.mem.eql(u8, candidate_key.?, selector.?)) {
            return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "alias")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "name")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "address")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "publicKey")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "suiAddress")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
    }

    return null;
}

pub fn parseFirstKey(allocator: std.mem.Allocator, contents: []const u8) !?[]const u8 {
    return parseKeyFromArray(allocator, contents, null);
}

pub fn parseKeyBySelector(allocator: std.mem.Allocator, contents: []const u8, selector: []const u8) !?[]const u8 {
    return parseKeyFromArray(allocator, contents, selector);
}

pub fn resolveSelectedKeyFromDefaultKeystore(allocator: std.mem.Allocator, selector: []const u8) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try parseKeyBySelector(allocator, contents, selector);
}

pub fn resolveFirstKeyFromDefaultKeystore(allocator: std.mem.Allocator) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try parseFirstKey(allocator, contents);
}

fn stringField(obj: std.json.ObjectMap, key_name: []const u8) ?[]const u8 {
    if (obj.get(key_name)) |value| {
        if (value == .string and value.string.len > 0) return value.string;
    }
    return null;
}

fn selectorFromObject(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "privateKey")) |value| return value;
    if (stringField(obj, "key")) |value| return value;
    if (stringField(obj, "value")) |value| return value;
    return null;
}

fn addressField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "address")) |value| return value;
    if (stringField(obj, "suiAddress")) |value| return value;
    return null;
}

fn findEntryBySelector(entries: []const std.json.Value, selector: []const u8) ?std.json.Value {
    const index_selector = std.fmt.parseInt(usize, selector, 10) catch null;
    if (index_selector) |target| {
        if (target >= entries.len) return null;
        return entries[target];
    }

    for (entries) |entry| {
        switch (entry) {
            .string => |value| {
                if (std.mem.eql(u8, value, selector)) return entry;
            },
            .object => |obj| {
                if (selectorFromObject(obj)) |value| {
                    if (std.mem.eql(u8, value, selector)) return entry;
                }
                if (stringField(obj, "alias")) |value| {
                    if (std.mem.eql(u8, value, selector)) return entry;
                }
                if (stringField(obj, "name")) |value| {
                    if (std.mem.eql(u8, value, selector)) return entry;
                }
                if (stringField(obj, "address")) |value| {
                    if (std.mem.eql(u8, value, selector)) return entry;
                }
                if (stringField(obj, "suiAddress")) |value| {
                    if (std.mem.eql(u8, value, selector)) return entry;
                }
            },
            else => {},
        }
    }

    return null;
}

pub fn resolveAddressFromKeystoreContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: []const u8,
) !?[]const u8 {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .array or parsed.value.array.items.len == 0) return null;

    const found = findEntryBySelector(parsed.value.array.items, selector) orelse return null;
    return switch (found) {
        .string => |value| try allocator.dupe(u8, value),
        .object => |obj| if (addressField(obj)) |value| try allocator.dupe(u8, value) else null,
        else => null,
    };
}

pub fn resolveAddressBySelector(allocator: std.mem.Allocator, selector: []const u8) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try resolveAddressFromKeystoreContents(allocator, contents, selector);
}

fn resolveSenderFromContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: []const u8,
) !?struct {
    value: []const u8,
    owned: bool,
} {
    if (selector.len == 0) return null;
    if (std.mem.startsWith(u8, selector, "0x")) {
        return .{ .value = selector, .owned = false };
    }

    if (try resolveAddressFromKeystoreContents(allocator, contents, selector)) |value| {
        return .{ .value = value, .owned = true };
    }
    return null;
}

fn signaturesContain(signatures: []const []const u8, value: []const u8) bool {
    for (signatures) |signature| {
        if (std.mem.eql(u8, signature, value)) return true;
    }
    return false;
}

pub fn prepareProgrammaticRequestFromContents(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    contents: []const u8,
    preparation: SignerPreparation,
) !PreparedProgrammaticRequest {
    var prepared = PreparedProgrammaticRequest{ .request = base_request };
    errdefer prepared.deinit(allocator);

    if (base_request.sender) |sender| {
        if (sender.len > 0) {
            const resolved_sender = try resolveSenderFromContents(allocator, contents, sender) orelse return error.InvalidCli;
            if (resolved_sender.owned) prepared.owned_sender = resolved_sender.value;
            prepared.request.sender = resolved_sender.value;
        }
    } else if (preparation.infer_sender_from_signers and preparation.signer_selectors.len > 0) {
        var has_resolver_input = false;
        for (preparation.signer_selectors) |selector| {
            if (selector.len == 0) continue;
            has_resolver_input = true;
            const resolved_sender = try resolveSenderFromContents(allocator, contents, selector) orelse continue;
            if (resolved_sender.owned) prepared.owned_sender = resolved_sender.value;
            prepared.request.sender = resolved_sender.value;
            break;
        }
        if (has_resolver_input and prepared.request.sender == null) return error.InvalidCli;
    }

    if (preparation.signer_selectors.len == 0 and (!preparation.from_keystore or base_request.signatures.len > 0)) {
        return prepared;
    }

    if (base_request.signatures.len > 0) {
        try prepared.combined_signatures.appendSlice(allocator, base_request.signatures);
    }

    if (preparation.signer_selectors.len > 0) {
        for (preparation.signer_selectors) |selector| {
            if (selector.len == 0) continue;
            const selector_key = try parseKeyBySelector(allocator, contents, selector) orelse return error.InvalidCli;
            if (signaturesContain(prepared.combined_signatures.items, selector_key)) {
                allocator.free(selector_key);
                continue;
            }
            try prepared.combined_signatures.append(allocator, selector_key);
            try prepared.owned_signatures.append(allocator, selector_key);
        }
    } else if (preparation.from_keystore and prepared.combined_signatures.items.len == 0) {
        const key = try parseFirstKey(allocator, contents) orelse return error.InvalidCli;
        try prepared.combined_signatures.append(allocator, key);
        try prepared.owned_signatures.append(allocator, key);
    }

    prepared.request.signatures = prepared.combined_signatures.items;
    return prepared;
}

pub fn prepareProgrammaticRequestFromDefaultKeystore(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    preparation: SignerPreparation,
) !PreparedProgrammaticRequest {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return error.InvalidCli;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCli,
        else => return err,
    };
    defer allocator.free(contents);

    return try prepareProgrammaticRequestFromContents(allocator, base_request, contents, preparation);
}

pub fn prepareResolvedProgrammaticRequestFromContents(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    contents: []const u8,
    preparation: SignerPreparation,
) !tx_builder.PreparedProgrammaticTxRequest {
    var prepared = try prepareProgrammaticRequestFromContents(allocator, base_request, contents, preparation);
    defer prepared.deinit(allocator);
    return try prepared.request.prepare(allocator);
}

pub fn prepareResolvedProgrammaticRequestFromDefaultKeystore(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    preparation: SignerPreparation,
) !tx_builder.PreparedProgrammaticTxRequest {
    var prepared = try prepareProgrammaticRequestFromDefaultKeystore(allocator, base_request, preparation);
    defer prepared.deinit(allocator);
    return try prepared.request.prepare(allocator);
}

test "prepareProgrammaticRequestFromContents resolves sender and signatures from signers" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xbuilder", prepared.request.sender.?);
    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "prepareProgrammaticRequestFromContents appends first key when requested" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .from_keystore = true },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "prepareProgrammaticRequestFromContents preserves existing signatures without duplication" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
            .signatures = &.{"sig-base"},
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-base", prepared.request.signatures[0]);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[1]);
}

test "prepareResolvedProgrammaticRequestFromContents normalizes commands and signer-backed data" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareResolvedProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expect(prepared.request.source.commands_json != null);
    try testing.expectEqualStrings("0xbuilder", prepared.request.sender.?);
    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}
