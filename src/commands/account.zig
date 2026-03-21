/// commands/account.zig - Account commands
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

/// Account information
pub const AccountInfo = struct {
    address: []const u8,
    balance: u64,
    object_count: u64,

    pub fn deinit(self: *AccountInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
    }
};

/// List accounts
pub fn listAccounts(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Accounts:\n");
}

/// Get account info
pub fn getAccountInfo(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    const selector = args.account_selector orelse return error.InvalidCli;

    if (args.account_info_json) {
        try writer.print("{{\"address\":\"{s}\"}}\n", .{selector});
    } else {
        try writer.print("Address: {s}\n", .{selector});
    }
}

/// Get account balance
pub fn getAccountBalance(
    allocator: std.mem.Allocator,
    address: []const u8,
) !u64 {
    _ = allocator;
    _ = address;
    return 0;
}

/// Get account coins
pub fn getAccountCoins(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Coins:\n");
}

/// Get account objects
pub fn getAccountObjects(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Objects:\n");
}

/// Format account info
pub fn formatAccountInfo(
    writer: anytype,
    info: *const AccountInfo,
    pretty: bool,
) !void {
    if (pretty) {
        try writer.print("Address: {s}\n", .{info.address});
        try writer.print("Balance: {d}\n", .{info.balance});
        try writer.print("Objects: {d}\n", .{info.object_count});
    } else {
        try writer.print("{s},{d},{d}\n", .{ info.address, info.balance, info.object_count });
    }
}

// ============================================================
// Tests
// ============================================================

test "getAccountInfo requires selector" {
    const testing = std.testing;

    const MockArgs = struct {
        account_selector: ?[]const u8 = null,
        account_info_json: bool = false,
    };

    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    const result = getAccountInfo(testing.allocator, &args, output.writer());
    try testing.expectError(error.InvalidCli, result);
}

test "AccountInfo lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const address = try allocator.dupe(u8, "0x123");
    var info = AccountInfo{
        .address = address,
        .balance = 1000,
        .object_count = 5,
    };
    defer info.deinit(allocator);

    try testing.expectEqual(@as(u64, 1000), info.balance);
    try testing.expectEqual(@as(u64, 5), info.object_count);
}

test "formatAccountInfo" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const address = try allocator.dupe(u8, "0xabc");
    const info = AccountInfo{
        .address = address,
        .balance = 500,
        .object_count = 3,
    };
    defer allocator.free(address);

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try formatAccountInfo(output.writer(), &info, true);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "0xabc"));
}
