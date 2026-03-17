const std = @import("std");
const client = @import("sui_client_zig");
const cli = @import("./cli.zig");
const tx_builder = client.tx_builder;
const RpcRequest = @typeInfo(@typeInfo(@typeInfo(client.rpc_client.RequestSender).@"struct".fields[1].type).pointer.child).@"fn".params[2].type.?;

fn sendExecuteAndMaybeWaitForConfirmation(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    payload: []const u8,
    writer: anytype,
) !void {
    const response = if (args.tx_send_wait)
        try rpc.executePayloadAndConfirm(
            payload,
            args.confirm_timeout_ms orelse std.math.maxInt(u64),
            args.confirm_poll_ms,
        )
    else
        try rpc.sendTxExecute(payload);
    defer rpc.allocator.free(response);
    try printResponse(allocator, writer, response, args.pretty);
}

fn printResponse(allocator: std.mem.Allocator, writer: anytype, response: []const u8, pretty: bool) !void {
    if (!pretty) {
        try writer.print("{s}\n", .{response});
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    try writer.print("{f}\n", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
}

fn writeOptionalJsonArray(
    allocator: std.mem.Allocator,
    writer: anytype,
    raw: ?[]const u8,
) !void {
    const value = raw orelse "[]";
    const trimmed = std.mem.trim(u8, value, " \n\r\t");
    if (trimmed.len == 0) {
        try writer.writeAll("[]");
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidCli;
    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
}

fn writeMoveCallInstruction(
    allocator: std.mem.Allocator,
    writer: anytype,
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    type_args: ?[]const u8,
    call_args: ?[]const u8,
) !void {
    try tx_builder.writeMoveCallInstruction(allocator, writer, package_id, module, function_name, type_args, call_args);
}

fn resolveProgrammaticCommandsFromArgs(
    allocator: std.mem.Allocator,
    command_items: []const []const u8,
    commands_json: ?[]const u8,
    package_id: ?[]const u8,
    module: ?[]const u8,
    function_name: ?[]const u8,
    type_args: ?[]const u8,
    args: ?[]const u8,
) ![]u8 {
    return try tx_builder.resolveCommands(allocator, .{
        .command_items = command_items,
        .commands_json = commands_json,
        .move_call = if (package_id != null and module != null and function_name != null)
            .{
                .package_id = package_id.?,
                .module = module.?,
                .function_name = function_name.?,
                .type_args = type_args,
                .arguments = args,
            }
        else
            null,
    });
}

fn appendNormalizedCommandJson(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    out: *std.ArrayList(u8),
    has_output: *bool,
) !void {
    const normalized = try normalizeProgrammaticCommandsFromArgs(allocator, commands_json);
    defer allocator.free(normalized);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized, .{});
    defer parsed.deinit();

    for (parsed.value.array.items) |entry| {
        if (has_output.*) {
            try out.append(allocator, ',');
        }
        const writer = out.writer(allocator);
        try writer.print("{f}", .{std.json.fmt(entry, .{})});
        has_output.* = true;
    }
}

fn normalizeProgrammaticCommandsFromArgs(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, commands_json, " \n\r\t");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    switch (parsed.value) {
        .array => |array| {
            if (array.items.len == 0) return error.InvalidCli;
            for (array.items) |entry| {
                validateProgrammaticCommandEntry(entry) catch |err| switch (err) {
                    error.InvalidCli => return error.InvalidCli,
                    else => return err,
                };
            }
            return try allocator.dupe(u8, trimmed);
        },
        .object => {
            validateProgrammaticCommandEntry(parsed.value) catch |err| switch (err) {
                error.InvalidCli => return error.InvalidCli,
                else => return err,
            };

            var out = std.ArrayList(u8){};
            errdefer out.deinit(allocator);
            const writer = out.writer(allocator);
            try writer.writeAll("[");
            try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
            try writer.writeAll("]");
            return out.toOwnedSlice(allocator);
        },
        else => return error.InvalidCli,
    }
}

fn validateProgrammaticCommandEntry(entry: std.json.Value) !void {
    try tx_builder.validateCommandEntry(entry);
}

fn hasTxBuildMoveCallArgs(parsed: *const cli.ParsedArgs) bool {
    return parsed.tx_build_package != null or
        parsed.tx_build_module != null or
        parsed.tx_build_function != null or
        parsed.tx_build_type_args != null or
        parsed.tx_build_args != null;
}

fn hasCompleteTxBuildMoveCallArgs(parsed: *const cli.ParsedArgs) bool {
    return parsed.tx_build_package != null and
        parsed.tx_build_module != null and
        parsed.tx_build_function != null;
}

fn hasTxBuildProgrammaticCommands(parsed: *const cli.ParsedArgs) bool {
    return parsed.tx_build_commands != null or parsed.tx_build_command_items.items.len > 0;
}

fn validateTxBuildArguments(args: *const cli.ParsedArgs) !void {
    switch (args.tx_build_kind orelse return error.InvalidCli) {
        .move_call => {
            if (hasTxBuildProgrammaticCommands(args)) return error.InvalidCli;
            if (!hasCompleteTxBuildMoveCallArgs(args)) return error.InvalidCli;
        },
        .programmable => {
            if (hasTxBuildMoveCallArgs(args)) return error.InvalidCli;
            if (!hasTxBuildProgrammaticCommands(args)) return error.InvalidCli;
        },
    }
}

const TxInspectPayload = []const u8;
const TxExecutePayload = []const u8;

fn buildInspectPayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !TxInspectPayload {
    return try @import("./tx_pipeline.zig").buildInspectPayloadFromArgs(allocator, args);
}

fn buildExecutePayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    non_programmatic_default: ?[]const u8,
) !TxExecutePayload {
    return try @import("./tx_pipeline.zig").buildExecutePayloadFromArgs(
        allocator,
        args,
        signatures,
        non_programmatic_default,
    );
}

fn commandSourceFromArgs(args: *const cli.ParsedArgs) tx_builder.CommandSource {
    return @import("./tx_pipeline.zig").commandSourceFromArgs(args);
}

fn programmaticRequestOptionsFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) client.tx_request_builder.ProgrammaticRequestOptions {
    return @import("./tx_pipeline.zig").programmaticRequestOptionsFromArgs(args, signatures);
}

fn programmaticAuthorizationPlanFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) client.tx_request_builder.AuthorizationPlan {
    return @import("./tx_pipeline.zig").programmaticAuthorizationPlanFromArgs(args, signatures);
}

fn programmaticAuthorizationPlanFromArgsWithAccountProvider(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?client.tx_request_builder.AccountProvider,
) client.tx_request_builder.AuthorizationPlan {
    return @import("./tx_pipeline.zig").programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, provider);
}

fn resolvedProgrammaticProvider(
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
) ?client.tx_request_builder.AccountProvider {
    return provider orelse @import("./tx_pipeline.zig").defaultProgrammaticAccountProviderFromArgs(args);
}

fn resolvedTxBuildSenderFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !?[]const u8 {
    return try @import("./tx_pipeline.zig").resolvedTxBuildSenderFromArgs(allocator, args);
}

fn buildTxBuildTransactionBlockFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) ![]u8 {
    return try @import("./tx_pipeline.zig").buildTxBuildTransactionBlockFromArgs(allocator, args);
}

fn buildTxBuildInstructionFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) ![]u8 {
    return try @import("./tx_pipeline.zig").buildTxBuildInstructionFromArgs(allocator, args);
}

fn buildExecutePayload(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    signatures: []const []const u8,
    options_json: ?[]const u8,
) ![]u8 {
    return try tx_builder.buildExecutePayload(allocator, tx_bytes, signatures, options_json);
}

fn buildProgrammaticTxExecutePayload(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    signatures: []const []const u8,
    options_json: ?[]const u8,
) ![]u8 {
    return try tx_builder.buildProgrammaticTxExecutePayload(
        allocator,
        commands_json,
        sender,
        gas_budget,
        gas_price,
        signatures,
        options_json,
    );
}

fn buildProgrammaticTxSimulatePayload(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    options_json: ?[]const u8,
) ![]u8 {
    return try tx_builder.buildProgrammaticTxSimulatePayload(
        allocator,
        commands_json,
        sender,
        gas_budget,
        gas_price,
        options_json,
    );
}

pub fn runCommandWithProgrammaticProvider(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
    programmatic_provider: ?client.tx_request_builder.AccountProvider,
) !void {
    const effective_programmatic_provider = if (cli.supportsProgrammableInput(args))
        resolvedProgrammaticProvider(args, programmatic_provider)
    else
        null;

    switch (args.command) {
        .help => try cli.printUsage(writer),
        .version => {
            const version = @import("sui_client_zig").version;
            try writer.print("sui-zig-rpc-client {d}.{d}.{d}\n", .{ version.major, version.minor, version.patch });
        },
        .account_list => {},
        .account_info => {},
        .rpc => {
            const method = args.method orelse return error.InvalidCli;
            const params = args.params orelse "[]";
            const response = try rpc.call(method, params);
            defer rpc.allocator.free(response);
            try printResponse(allocator, writer, response, args.pretty);
        },
        .tx_build => {
            const kind = args.tx_build_kind orelse return error.InvalidCli;
            try validateTxBuildArguments(args);

            switch (kind) {
                .move_call => {
                    if (args.tx_build_emit_tx_block) {
                        const tx_block = try buildTxBuildTransactionBlockFromArgs(allocator, args);
                        defer allocator.free(tx_block);
                        try writer.print("{s}", .{tx_block});
                    } else {
                        const instruction = try buildTxBuildInstructionFromArgs(allocator, args);
                        defer allocator.free(instruction);
                        try writer.print("{s}\n", .{instruction});
                    }
                },
                .programmable => {
                    const tx_block = try buildTxBuildTransactionBlockFromArgs(allocator, args);
                    defer allocator.free(tx_block);
                    try writer.print("{s}", .{tx_block});
                },
            }
        },
        .tx_simulate => {
            if (cli.supportsProgrammableInput(args)) {
                const response = try rpc.inspectPlan(
                    allocator,
                    programmaticAuthorizationPlanFromArgsWithAccountProvider(args, &.{}, effective_programmatic_provider),
                );
                defer rpc.allocator.free(response);
                try printResponse(allocator, writer, response, args.pretty);
                return;
            }
            const params = try buildInspectPayloadFromArgs(allocator, args);
            defer allocator.free(params);
            const response = try rpc.sendTxInspect(params);
            defer rpc.allocator.free(response);
            try printResponse(allocator, writer, response, args.pretty);
        },
        .tx_payload => {
            const signatures = if (args.signatures.items.len > 0) args.signatures.items else &.{};
            const payload = if (cli.supportsProgrammableInput(args) and effective_programmatic_provider != null)
                try programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, effective_programmatic_provider).buildAuthorizedExecutePayload(allocator)
            else
                try buildExecutePayloadFromArgs(allocator, args, signatures, null);
            defer allocator.free(payload);
            try printResponse(allocator, writer, payload, args.pretty);
        },
        .tx_send => {
            const provider_can_execute = if (effective_programmatic_provider) |provider|
                client.tx_request_builder.accountProviderCanExecute(provider)
            else
                false;
            if (args.signatures.items.len == 0 and (!cli.supportsProgrammableInput(args) or !provider_can_execute)) {
                return error.InvalidCli;
            }
            if (cli.supportsProgrammableInput(args)) {
                if (args.tx_bytes != null) return error.InvalidCli;
                const response = try rpc.executePlan(
                    allocator,
                    programmaticAuthorizationPlanFromArgsWithAccountProvider(args, args.signatures.items, effective_programmatic_provider),
                );
                defer rpc.allocator.free(response);
                try printResponse(allocator, writer, response, args.pretty);
                return;
            }
            const payload = try buildExecutePayloadFromArgs(
                allocator,
                args,
                args.signatures.items,
                null,
            );
            defer allocator.free(payload);
            try sendExecuteAndMaybeWaitForConfirmation(allocator, rpc, args, payload, writer);
        },
        .tx_status => {
            const digest = args.tx_digest orelse return error.InvalidCli;
            if (std.mem.eql(u8, digest, "")) return error.InvalidCli;
            const params = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{digest});
            defer allocator.free(params);
            const response = try rpc.getTransactionBlock(params);
            defer rpc.allocator.free(response);
            try printResponse(allocator, writer, response, args.pretty);
        },
        .tx_confirm => {
            const digest = args.tx_digest orelse return error.InvalidCli;
            if (std.mem.eql(u8, digest, "")) return error.InvalidCli;
            const response = try rpc.waitForTransactionConfirmation(
                digest,
                args.confirm_timeout_ms orelse std.math.maxInt(u64),
                args.confirm_poll_ms,
            );
            defer rpc.allocator.free(response);
            try printResponse(allocator, writer, response, args.pretty);
        },
    }
}

pub fn runCommand(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    return try runCommandWithProgrammaticProvider(allocator, rpc, args, writer, null);
}

test "runCommand tx_payload writes expected payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "AAABBB",
        .tx_options = "{\"skipChecks\":true}",
    };
    try args.signatures.append(allocator, "sig-a");
    try args.signatures.append(allocator, "sig-b");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    try runCommand(allocator, &rpc, &args, writer);
    try testing.expectEqualStrings("[\"AAABBB\",[\"sig-a\",\"sig-b\"],{\"skipChecks\":true}]\n", output.items);
}

test "runCommand tx_payload rejects non-object options for raw tx bytes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "AAABBB",
        .tx_options = "[\"skipChecks\"]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand help writes usage" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .help,
        .has_command = true,
    };
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "Usage:") != null);
}

test "buildExecutePayload includes signatures and optional options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildExecutePayload(
        allocator,
        "base64-tx-bytes",
        &.{ "sig-a", "sig-b" },
        "{\"skipChecks\":true}",
    );
    defer allocator.free(payload);

    try testing.expectEqualStrings(
        "[\"base64-tx-bytes\",[\"sig-a\",\"sig-b\"],{\"skipChecks\":true}]",
        payload,
    );
}

test "buildExecutePayload rejects non-object options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(
        error.InvalidCli,
        buildExecutePayload(allocator, "base64-tx-bytes", &.{}, "[\"skipChecks\"]"),
    );
}

test "buildExecutePayload no signatures and no options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildExecutePayload(
        allocator,
        "base64-tx-bytes",
        &.{},
        null,
    );
    defer allocator.free(payload);

    try testing.expectEqualStrings("[\"base64-tx-bytes\",[]]", payload);
}

test "buildProgrammaticTxExecutePayload includes programmatic tx metadata" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildProgrammaticTxExecutePayload(
        allocator,
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        "0xabc",
        1200,
        9,
        &.{ "sig-a" },
        "{\"skipChecks\":true}",
    );
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expect(parsed.value.array.items[0] == .string);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, parsed.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expect(tx_block.value == .object);
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), tx_block.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), tx_block.value.object.get("gasPrice").?.integer);

    const signatures = parsed.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
}

test "buildProgrammaticTxExecutePayload rejects invalid command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, buildProgrammaticTxExecutePayload(
        allocator,
        "{\"kind\":\"MoveCall\"}",
        null,
        null,
        null,
        &.{},
        null,
    ));
}

test "resolveProgrammaticCommandsFromArgs builds move-call command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        null,
        "0x2",
        "counter",
        "increment",
        "[]",
        "[\"0xabc\"]",
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
}

test "resolveProgrammaticCommandsFromArgs validates explicit command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "{\"kind\":\"CustomFutureCommand\",\"value\":1}",
        null,
        null,
        null,
        null,
        null,
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    try testing.expectEqualStrings("CustomFutureCommand", parsed.value.array.items[0].object.get("kind").?.string);
}

test "resolveProgrammaticCommandsFromArgs accepts single command object and normalizes to array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
        null,
        null,
        null,
        null,
        null,
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    const command = parsed.value.array.items[0].object;
    const kind = command.get("kind") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("MoveCall", kind.string);
}

test "resolveProgrammaticCommandsFromArgs validates command object shape" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[\"MoveCall\"]",
        null,
        null,
        null,
        null,
        null,
    ));
    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[{\"package\":\"0x2\",\"module\":\"m\",\"function\":\"f\"}]",
        null,
        null,
        null,
        null,
        null,
    ));
    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[{\"kind\":\"MoveCall\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[]}]",
        null,
        null,
        null,
        null,
        null,
    ));
    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"]}]",
        null,
        null,
        null,
        null,
        null,
    ));
}

test "resolveProgrammaticCommandsFromArgs rejects empty command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[]",
        null,
        null,
        null,
        null,
        null,
    ));
}

test "resolveProgrammaticCommandsFromArgs merges --command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const fragment_items = [_][]const u8{
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
    };

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &fragment_items,
        "[{\"kind\":\"MoveCall\",\"package\":\"0x1\",\"module\":\"mod\",\"function\":\"f\",\"typeArguments\":[],\"arguments\":[]}]",
        null,
        null,
        null,
        null,
        null,
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[2].object.get("kind").?.string);
}

test "supportsProgrammableInput detects command and move-call shapes" {
    const testing = std.testing;

    const no_args = cli.ParsedArgs{};
    try testing.expect(!cli.supportsProgrammableInput(&no_args));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var command_item_args = cli.ParsedArgs{};
    defer command_item_args.deinit(allocator);
    try command_item_args.tx_build_command_items.append(allocator, "{}");
    try testing.expect(cli.supportsProgrammableInput(&command_item_args));

    const command_args = cli.ParsedArgs{ .tx_build_commands = "[]", .tx_build_package = "0x2", .tx_build_module = "m", .tx_build_function = "f" };
    try testing.expect(cli.supportsProgrammableInput(&command_args));

    const move_call_args = cli.ParsedArgs{ .tx_build_package = "0x2", .tx_build_module = "m", .tx_build_function = "f" };
    try testing.expect(cli.supportsProgrammableInput(&move_call_args));
}

test "buildProgrammaticTxSimulatePayload includes gas and sender context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildProgrammaticTxSimulatePayload(
        allocator,
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        "0xabc",
        1200,
        9,
        "{\"skipChecks\":true}",
    );
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expect(parsed.value.array.items[0] == .string);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, parsed.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), tx_block.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), tx_block.value.object.get("gasPrice").?.integer);

    const context = parsed.value.array.items[1].object;
    try testing.expectEqualStrings("0xabc", context.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), context.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), context.get("gasPrice").?.integer);
    try testing.expect(context.get("options") != null);
    try testing.expect(context.get("options").?.object.get("skipChecks") != null);
}

test "runCommand tx_simulate with commands sends inspect request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_options = "{\"skipChecks\":true}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}\n", output.items);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 2), params.value.array.items.len);

    const context = params.value.array.items[1].object;
    try testing.expectEqualStrings("0xabc", context.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), context.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 7), context.get("gasPrice").?.integer);
    try testing.expect(context.get("options") != null);
}

test "runCommand tx_simulate move-call sends inspect request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 11,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct { saw_request: *bool, params_text: *?[]const u8 };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            _ = req.method;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":true}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    const commands = tx_block.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    const instruction = commands.items[0];
    try testing.expectEqualStrings("MoveCall", instruction.object.get("kind").?.string);
}

test "runCommand tx_simulate accepts single command object input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"ok\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    const commands = tx_block.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
}

test "runCommand tx_simulate rejects incomplete move-call context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_payload with commands builds execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    const items = payload.value.array.items;
    try testing.expectEqual(@as(usize, 2), items.len);
    try testing.expect(items[0] == .string);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), tx_block.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 8), tx_block.value.object.get("gasPrice").?.integer);

    try testing.expect(items[1] == .array);
    const signatures = items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
}

test "runCommand tx_payload move-call builds execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    const tx = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx.value.object.get("kind").?.string);
    const commands = tx.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
    try testing.expect(payload.value.array.items[1].array.items.len == 1);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_payload rejects incomplete move-call context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_confirm waits for transaction result" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_confirm,
        .has_command = true,
        .tx_digest = "0xabc",
        .confirm_poll_ms = 1,
        .confirm_timeout_ms = 5000,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var call_count: usize = 0;
    const MockContext = struct {
        saw_request: *bool,
        call_count: *usize,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.call_count.* += 1;

            if (ctx.call_count.* == 1) {
                return alloc.dupe(u8, "{\"result\":null}");
            }
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\",\"effects\":{\"status\":\"success\"}}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .call_count = &call_count,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);
    try testing.expectEqual(@as(usize, 2), call_count);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\",\"effects\":{\"status\":\"success\"}}}\n", output.items);
}

test "runCommand tx_send with commands sends execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_options = "{\"skipChecks\":true}",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"executed\":true}}\n", output.items);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 3), params.value.array.items.len);

    const tx_block_payload = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block_payload.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block_payload.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block_payload.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), tx_block_payload.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 7), tx_block_payload.value.object.get("gasPrice").?.integer);
    try testing.expect(params.value.array.items[1] == .array);
    const signatures = params.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
    try testing.expect(params.value.array.items[2] == .object);
    try testing.expect(params.value.array.items[2].object.get("skipChecks") != null);
}

test "runCommand tx_send move-call sends execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);
    try testing.expect(method_ok);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 800), tx_block.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 6), tx_block.value.object.get("gasPrice").?.integer);
    const signatures = params.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
}

test "runCommand tx_send rejects incomplete move-call context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_sender = "0xabc",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_send with --wait confirms transaction" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_send_wait = true,
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_execute_request = false;
    var saw_confirm_request = false;

    const MockContext = struct {
        saw_execute_request: *bool,
        saw_confirm_request: *bool,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.saw_execute_request.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.saw_confirm_request.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_execute_request = &saw_execute_request,
        .saw_confirm_request = &saw_confirm_request,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_execute_request);
    try testing.expect(saw_confirm_request);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}\n", output.items);
}

test "runCommand tx_send rejects tx-bytes with programmable inputs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_bytes = "dGVzdF90eF9ieXRlcw==",
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_send rejects empty tx_send payload input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
    };
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_payload rejects empty payload input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
    };
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_payload rejects tx-bytes with programmable inputs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "dGVzdF90eF9ieXRlcw==",
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_build move-call prints instruction JSON" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "[\"0xabc\",1]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const kind = parsed.value.object.get("kind").?;
    try testing.expect(kind == .string);
    try testing.expectEqualStrings("MoveCall", kind.string);
    const package_id = parsed.value.object.get("package").?;
    try testing.expect(package_id == .string);
    try testing.expectEqualStrings("0x2", package_id.string);
    const module = parsed.value.object.get("module").?;
    try testing.expect(module == .string);
    try testing.expectEqualStrings("counter", module.string);
    const function_name = parsed.value.object.get("function").?;
    try testing.expect(function_name == .string);
    try testing.expectEqualStrings("increment", function_name.string);
    const type_arguments = parsed.value.object.get("typeArguments").?;
    try testing.expect(type_arguments == .array);
    try testing.expect(type_arguments.array.items.len == 1);
    const call_args = parsed.value.object.get("arguments").?;
    try testing.expect(call_args == .array);
    try testing.expect(call_args.array.items.len == 2);
}

test "runCommand tx_build move-call with emit-tx-block includes gas metadata" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const kind = parsed.value.object.get("kind").?;
    try testing.expectEqualStrings("ProgrammableTransaction", kind.string);
    try testing.expect(parsed.value.object.get("sender").? == .string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expect(parsed.value.object.get("gasBudget").? == .integer);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gasBudget").?.integer);
    try testing.expect(parsed.value.object.get("gasPrice").? == .integer);
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("gasPrice").?.integer);
    const commands = parsed.value.object.get("commands").?;
    try testing.expect(commands == .array);
    try testing.expect(commands.array.items.len == 1);
    const instruction = commands.array.items[0];
    try testing.expect(instruction == .object);
    try testing.expectEqualStrings("MoveCall", instruction.object.get("kind").?.string);
}

test "runCommand tx_build programmable outputs transaction block" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gasBudget").?.integer);
    const commands = parsed.value.object.get("commands").?;
    try testing.expect(commands == .array);
    try testing.expectEqual(@as(usize, 1), commands.array.items.len);
    const instruction = commands.array.items[0];
    try testing.expectEqualStrings("MoveCall", instruction.object.get("kind").?.string);
}

test "runCommand tx_build programmable rejects invalid command json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "{\"kind\":\"\"}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_build programmable accepts single command object and repeatable command items" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };
    defer args.deinit(allocator);
    try args.tx_build_command_items.append(allocator, "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}");
    try args.tx_build_command_items.append(allocator, "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]");

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("gasPrice").?.integer);

    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", commands.items[1].object.get("kind").?.string);
}

test "runCommand tx_build programmable accepts single command object" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
}

test "runCommand tx_build move-call rejects command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_build programmable rejects move-call fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_build rejects invalid move-call array arguments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "\"not-an-array\"",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "printResponse supports pretty and compact modes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const response = "{\"result\":{\"tx\":\"abc\"},\"jsonrpc\":\"2.0\"}";

    var compact = std.ArrayList(u8){};
    defer compact.deinit(allocator);
    const compact_writer = compact.writer(allocator);
    try printResponse(allocator, compact_writer, response, false);
    try testing.expectEqualStrings("{\"result\":{\"tx\":\"abc\"},\"jsonrpc\":\"2.0\"}\n", compact.items);

    var pretty = std.ArrayList(u8){};
    defer pretty.deinit(allocator);
    const pretty_writer = pretty.writer(allocator);
    try printResponse(allocator, pretty_writer, response, true);

    const pretty_json = try std.json.parseFromSlice(std.json.Value, allocator, pretty.items, .{});
    defer pretty_json.deinit();

    try testing.expect(pretty_json.value == .object);
    try testing.expectEqualStrings("2.0", pretty_json.value.object.get("jsonrpc").?.string);
    try testing.expectEqualStrings("abc", pretty_json.value.object.get("result").?.object.get("tx").?.string);
    try testing.expect(std.mem.endsWith(u8, pretty.items, "\n"));
}
