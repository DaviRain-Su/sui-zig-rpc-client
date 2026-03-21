/// commands/tx.zig - 交易相关命令处理
const std = @import("std");
const client = @import("sui_client_zig");
const cli = @import("../cli.zig");
const shared = @import("shared.zig");
const tx_builder = client.tx_builder;

/// 发送交易执行并等待确认（如果需要）
pub fn sendExecuteAndMaybeWaitForConfirmation(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    payload: []const u8,
    writer: anytype,
) !void {
    if (args.tx_send_observe) {
        const response = try rpc.sendTxExecute(payload);
        defer rpc.allocator.free(response);

        var observation = try rpc.observeConfirmedExecuteResponse(
            allocator,
            response,
            args.confirm_timeout_ms orelse std.math.maxInt(u64),
            args.confirm_poll_ms,
        );
        defer observation.deinit(allocator);

        try shared.printStructuredJson(writer, observation, args.pretty);
        return;
    }

    const response = if (args.tx_send_wait)
        try rpc.executePayloadAndConfirm(
            payload,
            args.confirm_timeout_ms orelse std.math.maxInt(u64),
            args.confirm_poll_ms,
        )
    else
        try rpc.sendTxExecute(payload);
    defer rpc.allocator.free(response);

    if (args.tx_send_summarize) {
        var insights = try rpc.summarizeExecutionResponse(allocator, response);
        defer insights.deinit(allocator);
        try shared.printStructuredJson(writer, insights, args.pretty);
        return;
    }

    try shared.printResponse(allocator, writer, response, args.pretty);
}

/// 发送 dry-run 并可能汇总结果
pub fn sendDryRunAndMaybeSummarize(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    tx_bytes: []const u8,
    writer: anytype,
) !void {
    const payload = try tx_builder.buildDryRunPayload(allocator, tx_bytes);
    defer allocator.free(payload);

    const response = try rpc.sendTxDryRun(payload);
    defer rpc.allocator.free(response);

    if (args.tx_send_summarize) {
        var insights = try rpc.summarizeExecutionResponse(allocator, response);
        defer insights.deinit(allocator);
        try shared.printStructuredJson(writer, insights, args.pretty);
        return;
    }

    try shared.printResponse(allocator, writer, response, args.pretty);
}

/// 构建执行 payload（简化版本）
pub fn buildExecutePayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    options: ?[]const u8,
) ![]u8 {
    const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
    
    var arr = std.ArrayList(u8).init(allocator);
    defer arr.deinit();
    
    const writer = arr.writer();
    try writer.writeAll("[");
    
    // tx_bytes
    try std.json.stringify(tx_bytes, .{}, writer);
    try writer.writeAll(",");
    
    // signatures
    try writer.writeAll("[");
    for (signatures, 0..) |sig, i| {
        if (i > 0) try writer.writeAll(",");
        try std.json.stringify(sig, .{}, writer);
    }
    try writer.writeAll("]");
    
    // options
    if (options) |opts| {
        try writer.writeAll(",");
        try writer.writeAll(opts);
    } else if (args.tx_options) |opts| {
        try writer.writeAll(",");
        try writer.writeAll(opts);
    }
    
    try writer.writeAll("]");
    
    return arr.toOwnedSlice();
}

// ============================================================
// 测试
// ============================================================

test "buildExecutePayloadFromArgs builds correct payload" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_bytes = "AAABBB",
        .tx_options = "{\"skipChecks\":true}",
    };

    const signatures = &.{"sig-a", "sig-b"};
    const payload = try buildExecutePayloadFromArgs(allocator, &args, signatures, null);
    defer allocator.free(payload);

    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "AAABBB"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig-a"));
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig-b"));
}
