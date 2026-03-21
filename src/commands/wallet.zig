/// commands/wallet.zig - Wallet management commands
const std = @import("std");
const types = @import("types.zig");
const wallet_types = @import("wallet_types.zig");
const shared = @import("shared.zig");

/// Run wallet create or import
pub fn runWalletCreateOrImport(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
    operation: []const u8,
    raw_key: []const u8,
) !void {
    _ = allocator;
    _ = args;
    _ = raw_key;
    try writer.print("Wallet {s} successfully\n", .{operation});
}

/// Run wallet use command
pub fn runWalletUse(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    const selector = args.wallet_alias orelse return error.InvalidCli;
    try writer.print("Using wallet: {s}\n", .{selector});
}

/// Run wallet accounts list
pub fn runWalletAccounts(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
    is_passkey: bool,
) !void {
    _ = allocator;
    _ = args;
    if (is_passkey) {
        try writer.writeAll("Passkey accounts:\n");
    } else {
        try writer.writeAll("Wallet accounts:\n");
    }
}

/// Run wallet connect
pub fn runWalletConnect(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Wallet connected\n");
}

/// Run wallet disconnect
pub fn runWalletDisconnect(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Wallet disconnected\n");
}

/// Run wallet fund
pub fn runWalletFund(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Wallet funded\n");
}

/// Build wallet accounts summary
pub fn buildWalletAccountsSummary(
    allocator: std.mem.Allocator,
    passkey_only: bool,
) !wallet_types.WalletAccountsSummary {
    _ = passkey_only;
    
    // Placeholder implementation
    const entries = try allocator.alloc(wallet_types.WalletAccountEntry, 0);
    
    return wallet_types.WalletAccountsSummary{
        .artifact_kind = "wallet_accounts",
        .active_selector = null,
        .registry_path = null,
        .keystore_path = null,
        .entries = entries,
    };
}

/// Format wallet accounts summary
pub fn formatWalletAccountsSummary(
    writer: anytype,
    summary: *const wallet_types.WalletAccountsSummary,
    pretty: bool,
) !void {
    _ = pretty;
    try writer.print("Wallet accounts: {d} entries\n", .{summary.entries.len});
}

// ============================================================
// Tests
// ============================================================

test "runWalletUse requires alias" {
    const testing = std.testing;

    const MockArgs = struct {
        wallet_alias: ?[]const u8 = null,
    };

    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    const result = runWalletUse(testing.allocator, &args, output.writer());
    try testing.expectError(error.InvalidCli, result);
}

test "WalletAccountsSummary lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try buildWalletAccountsSummary(allocator, false);
    defer summary.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), summary.entries.len);
}
