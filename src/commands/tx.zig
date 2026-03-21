/// commands/tx.zig - Transaction commands
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

const client = @import("sui_client_zig");

/// Transaction kind
pub const TxKind = enum {
    transfer,
    move_call,
    programmable,
    publish,
    upgrade,
};

/// Transaction options
pub const TxOptions = struct {
    skip_checks: bool = false,
    show_raw_input: bool = false,
    show_effects: bool = false,
    show_events: bool = false,
    show_object_changes: bool = false,
    show_balance_changes: bool = false,
};

/// Send execute transaction and optionally wait for confirmation
pub fn sendExecuteAndMaybeWaitForConfirmation(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: anytype,
    payload: []const u8,
    writer: anytype,
) !void {
    const tx_send_observe = args.tx_send_observe;
    const tx_send_wait = args.tx_send_wait;
    const tx_send_summarize = args.tx_send_summarize;
    const confirm_timeout_ms = args.confirm_timeout_ms;
    const confirm_poll_ms = args.confirm_poll_ms;
    const pretty = args.pretty;

    if (tx_send_observe) {
        const response = try rpc.sendTxExecute(payload);
        defer rpc.allocator.free(response);

        const timeout = confirm_timeout_ms orelse std.math.maxInt(u64);
        var observation = try rpc.observeConfirmedExecuteResponse(
            allocator,
            response,
            timeout,
            confirm_poll_ms,
        );
        defer observation.deinit(allocator);

        try shared.printStructuredJson(writer, observation, pretty);
        return;
    }

    const response = if (tx_send_wait)
        try rpc.executePayloadAndConfirm(
            payload,
            confirm_timeout_ms orelse std.math.maxInt(u64),
            confirm_poll_ms,
        )
    else
        try rpc.sendTxExecute(payload);
    defer rpc.allocator.free(response);

    if (tx_send_summarize) {
        var insights = try rpc.summarizeExecutionResponse(allocator, response);
        defer insights.deinit(allocator);
        try shared.printStructuredJson(writer, insights, pretty);
        return;
    }

    try printResponse(allocator, writer, response, pretty);
}

/// Send dry-run transaction and optionally summarize
pub fn sendDryRunAndMaybeSummarize(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: anytype,
    tx_bytes: []const u8,
    writer: anytype,
) !void {
    const payload = try buildDryRunPayload(allocator, tx_bytes);
    defer allocator.free(payload);

    const response = try rpc.sendTxDryRun(payload);
    defer rpc.allocator.free(response);

    if (args.tx_send_summarize) {
        var insights = try rpc.summarizeExecutionResponse(allocator, response);
        defer insights.deinit(allocator);
        try shared.printStructuredJson(writer, insights, args.pretty);
        return;
    }

    try printResponse(allocator, writer, response, args.pretty);
}

/// Print RPC response
fn printResponse(
    allocator: std.mem.Allocator,
    writer: anytype,
    response: []const u8,
    pretty: bool,
) !void {
    if (!pretty) {
        try writer.print("{s}\n", .{response});
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    try writer.print("{f}\n", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
}

/// Build execute payload from args
pub fn buildExecutePayloadFromArgs(
    allocator: std.mem.Allocator,
    args: anytype,
    signatures: []const []const u8,
    options: ?[]const u8,
) ![]u8 {
    _ = args;
    
    var arr: std.ArrayList(u8) = .{};
    errdefer arr.deinit(allocator);

    const writer = arr.writer(allocator);
    try writer.writeAll("[");

    // tx_bytes placeholder
    try writer.writeAll("\"tx_bytes_placeholder\"");
    try writer.writeAll(",");

    // signatures
    try writer.writeAll("[");
    for (signatures, 0..) |sig, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("\"");
        try writer.writeAll(sig);
        try writer.writeAll("\"");
    }
    try writer.writeAll("]");

    // options
    if (options) |opts| {
        try writer.writeAll(",");
        try writer.writeAll(opts);
    }

    try writer.writeAll("]");

    return arr.toOwnedSlice(allocator);
}

/// Build payload from raw tx bytes and signatures
pub fn buildPayloadFromTxBytesAndSignatures(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    signatures: []const []const u8,
    options: ?[]const u8,
) ![]u8 {
    var arr: std.ArrayList(u8) = .{};
    errdefer arr.deinit(allocator);

    const writer = arr.writer(allocator);
    try writer.writeAll("[");

    // tx_bytes
    try writer.writeAll("\"");
    try writer.writeAll(tx_bytes);
    try writer.writeAll("\"");
    try writer.writeAll(",");

    // signatures
    try writer.writeAll("[");
    for (signatures, 0..) |sig, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("\"");
        try writer.writeAll(sig);
        try writer.writeAll("\"");
    }
    try writer.writeAll("]");

    // options
    if (options) |opts| {
        try writer.writeAll(",");
        try writer.writeAll(opts);
    }

    try writer.writeAll("]");

    return arr.toOwnedSlice(allocator);
}

/// Build dry-run payload
pub fn buildDryRunPayload(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
) ![]u8 {
    var arr: std.ArrayList(u8) = .{};
    errdefer arr.deinit(allocator);

    const writer = arr.writer(allocator);
    try writer.writeAll("[\"");
    try writer.writeAll(tx_bytes);
    try writer.writeAll("\"]");

    return arr.toOwnedSlice(allocator);
}

/// Build simulate payload
pub fn buildSimulatePayload(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    options: TxOptions,
) ![]u8 {
    var arr: std.ArrayList(u8) = .{};
    errdefer arr.deinit(allocator);

    const writer = arr.writer(allocator);
    try writer.writeAll("[\"");
    try writer.writeAll(tx_bytes);
    try writer.writeAll("\",");
    
    // Build options object
    try writer.writeAll("{");
    try writer.print("\"skipChecks\":{}", .{options.skip_checks});
    if (options.show_raw_input) try writer.writeAll(",\"showRawInput\":true");
    if (options.show_effects) try writer.writeAll(",\"showEffects\":true");
    if (options.show_events) try writer.writeAll(",\"showEvents\":true");
    if (options.show_object_changes) try writer.writeAll(",\"showObjectChanges\":true");
    if (options.show_balance_changes) try writer.writeAll(",\"showBalanceChanges\":true");
    try writer.writeAll("}");
    
    try writer.writeAll("]");

    return arr.toOwnedSlice(allocator);
}

/// Build transaction kind string
pub fn buildTxKindString(kind: TxKind) []const u8 {
    return switch (kind) {
        .transfer => "transfer",
        .move_call => "move_call",
        .programmable => "programmable",
        .publish => "publish",
        .upgrade => "upgrade",
    };
}

/// Run transaction simulate command
pub fn runTxSimulate(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
    
    var options = TxOptions{};
    if (args.tx_options) |opts| {
        // Parse options JSON
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, opts, .{});
        defer parsed.deinit();
        
        if (parsed.value.object.get("skipChecks")) |v| {
            if (v == .bool) options.skip_checks = v.bool;
        }
        if (parsed.value.object.get("showRawInput")) |v| {
            if (v == .bool) options.show_raw_input = v.bool;
        }
        if (parsed.value.object.get("showEffects")) |v| {
            if (v == .bool) options.show_effects = v.bool;
        }
        if (parsed.value.object.get("showEvents")) |v| {
            if (v == .bool) options.show_events = v.bool;
        }
        if (parsed.value.object.get("showObjectChanges")) |v| {
            if (v == .bool) options.show_object_changes = v.bool;
        }
        if (parsed.value.object.get("showBalanceChanges")) |v| {
            if (v == .bool) options.show_balance_changes = v.bool;
        }
    }
    
    const payload = try buildSimulatePayload(allocator, tx_bytes, options);
    defer allocator.free(payload);
    
    const response = try rpc.sendTxSimulate(payload);
    defer rpc.allocator.free(response);
    
    try printResponse(allocator, writer, response, args.pretty);
}

/// Run transaction dry-run command
pub fn runTxDryRun(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
    try sendDryRunAndMaybeSummarize(allocator, rpc, args, tx_bytes, writer);
}

/// Run transaction send command
pub fn runTxSend(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
    
    // Collect signatures
    var signatures: std.ArrayList([]const u8) = .{};
    defer signatures.deinit(allocator);
    
    // Add signatures from args
    if (@hasField(@TypeOf(args.*), "signatures")) {
        for (args.signatures.items) |sig| {
            try signatures.append(sig);
        }
    }
    
    const payload = try buildPayloadFromTxBytesAndSignatures(
        allocator,
        tx_bytes,
        signatures.items,
        args.tx_options,
    );
    defer allocator.free(payload);
    
    try sendExecuteAndMaybeWaitForConfirmation(allocator, rpc, args, payload, writer);
}

/// Run transaction payload command
pub fn runTxPayload(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
    
    // Collect signatures
    var signatures: std.ArrayList([]const u8) = .{};
    defer signatures.deinit(allocator);
    
    if (@hasField(@TypeOf(args.*), "signatures")) {
        for (args.signatures.items) |sig| {
            try signatures.append(sig);
        }
    }
    
    const payload = try buildPayloadFromTxBytesAndSignatures(
        allocator,
        tx_bytes,
        signatures.items,
        args.tx_options,
    );
    defer allocator.free(payload);
    
    if (args.tx_send_summarize) {
        // Build summary
        var summary = std.json.ObjectMap.init(allocator);
        defer summary.deinit();
        
        try summary.put("data_kind", .{ .string = "tx_bytes" });
        try summary.put("signature_count", .{ .integer = @intCast(signatures.items.len) });
        try summary.put("has_options", .{ .bool = args.tx_options != null });
        
        try shared.printStructuredJson(writer, summary, args.pretty);
    } else {
        try writer.print("{s}\n", .{payload});
    }
}

/// Validate transaction build arguments
pub fn validateTxBuildArguments(args: anytype) !void {
    _ = args;
    // Placeholder for validation logic
}

/// Build transaction block from args
pub fn buildTransactionBlockFromArgs(
    allocator: std.mem.Allocator,
    args: anytype,
) ![]u8 {
    _ = args;
    // Placeholder implementation
    return try allocator.dupe(u8, "{}");
}

// ============================================================
// Tests
// ============================================================

test "buildExecutePayloadFromArgs builds correct payload" {
    const testing = std.testing;

    const MockArgs = struct {
        tx_bytes: ?[]const u8 = "AAABBB",
        tx_options: ?[]const u8 = null,
        tx_send_observe: bool = false,
        tx_send_wait: bool = false,
        tx_send_summarize: bool = false,
        confirm_timeout_ms: ?u64 = null,
        confirm_poll_ms: u64 = 1000,
        pretty: bool = false,
    };

    var args = MockArgs{};
    const signatures = &.{"sig-a", "sig-b"};

    const payload = try buildExecutePayloadFromArgs(testing.allocator, &args, signatures, null);
    defer testing.allocator.free(payload);

    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig-a"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig-b"));
}

test "buildDryRunPayload" {
    const testing = std.testing;

    const payload = try buildDryRunPayload(testing.allocator, "tx_data");
    defer testing.allocator.free(payload);

    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "tx_data"));
}

test "buildSimulatePayload with options" {
    const testing = std.testing;

    const options = TxOptions{
        .skip_checks = true,
        .show_effects = true,
    };
    
    const payload = try buildSimulatePayload(testing.allocator, "tx_data", options);
    defer testing.allocator.free(payload);

    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "tx_data"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "skipChecks"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "showEffects"));
}

test "buildPayloadFromTxBytesAndSignatures" {
    const testing = std.testing;

    const payload = try buildPayloadFromTxBytesAndSignatures(
        testing.allocator,
        "tx_bytes_data",
        &.{"sig1", "sig2"},
        null,
    );
    defer testing.allocator.free(payload);

    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "tx_bytes_data"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig1"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig2"));
}

test "buildTxKindString" {
    const testing = std.testing;

    try testing.expectEqualStrings("transfer", buildTxKindString(.transfer));
    try testing.expectEqualStrings("move_call", buildTxKindString(.move_call));
    try testing.expectEqualStrings("programmable", buildTxKindString(.programmable));
    try testing.expectEqualStrings("publish", buildTxKindString(.publish));
    try testing.expectEqualStrings("upgrade", buildTxKindString(.upgrade));
}

test "validateTxBuildArguments placeholder" {
    const MockArgs = struct {};
    var args = MockArgs{};
    try validateTxBuildArguments(&args);
}

test "buildTransactionBlockFromArgs placeholder" {
    const testing = std.testing;
    const MockArgs = struct {};
    var args = MockArgs{};
    
    const result = try buildTransactionBlockFromArgs(testing.allocator, &args);
    defer testing.allocator.free(result);
    
    try testing.expectEqualStrings("{}", result);
}
