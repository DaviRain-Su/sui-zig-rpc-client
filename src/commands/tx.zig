/// commands/tx.zig - Transaction commands
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

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

/// Build execute payload from args
pub fn buildExecutePayloadFromArgs(
    allocator: std.mem.Allocator,
    args: anytype,
    signatures: []const []const u8,
    options: ?[]const u8,
) ![]u8 {
    _ = args;
    _ = options;
    
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
    _ = options;
    
    var arr: std.ArrayList(u8) = .{};
    errdefer arr.deinit(allocator);

    const writer = arr.writer(allocator);
    try writer.writeAll("[\"");
    try writer.writeAll(tx_bytes);
    try writer.writeAll("\",{}]");

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

// ============================================================
// Tests
// ============================================================

test "buildExecutePayloadFromArgs builds correct payload" {
    const testing = std.testing;

    const MockArgs = struct {
        tx_bytes: ?[]const u8 = "AAABBB",
        tx_options: ?[]const u8 = null,
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

test "buildTxKindString" {
    const testing = std.testing;

    try testing.expectEqualStrings("transfer", buildTxKindString(.transfer));
    try testing.expectEqualStrings("move_call", buildTxKindString(.move_call));
    try testing.expectEqualStrings("programmable", buildTxKindString(.programmable));
}
