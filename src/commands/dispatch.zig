/// commands/dispatch.zig - Command dispatch logic
///
/// This module provides the main command dispatch functionality.
/// It routes commands to the appropriate sub-module handlers.

const std = @import("std");
const types = @import("types.zig");
const wallet_types = @import("wallet_types.zig");
const shared = @import("shared.zig");
const provider = @import("provider.zig");
const wallet = @import("wallet.zig");
const tx = @import("tx.zig");
const move = @import("move.zig");
const account = @import("account.zig");

/// Command handler function type
pub const CommandHandler = fn (
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) anyerror!void;

/// Command router - dispatches commands to appropriate handlers
pub fn runCommand(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    const command = args.command;

    switch (command) {
        // Help and version
        .help => try handleHelp(writer),
        .version => try handleVersion(writer),

        // Wallet commands
        .wallet_create => try handleWalletCreate(allocator, args, writer),
        .wallet_import => try handleWalletImport(allocator, args, writer),
        .wallet_use => try wallet.runWalletUse(allocator, args, writer),
        .wallet_accounts => try wallet.runWalletAccounts(allocator, args, writer, false),
        .wallet_connect => try wallet.runWalletConnect(allocator, args, writer),
        .wallet_disconnect => try wallet.runWalletDisconnect(allocator, args, writer),
        .wallet_passkey_list => try wallet.runWalletAccounts(allocator, args, writer, true),
        .wallet_fund => try wallet.runWalletFund(allocator, args, writer),

        // Account commands
        .account_list => try account.listAccounts(allocator, args, writer),
        .account_info => try account.getAccountInfo(allocator, args, writer),
        .account_balance => try handleAccountBalance(allocator, rpc, args, writer),
        .account_coins => try account.getAccountCoins(allocator, args, writer),
        .account_objects => try account.getAccountObjects(allocator, args, writer),

        // Transaction commands
        .tx_simulate => try handleTxSimulate(allocator, rpc, args, writer),
        .tx_dry_run => try handleTxDryRun(allocator, rpc, args, writer),
        .tx_build => try handleTxBuild(allocator, args, writer),
        .tx_send => try handleTxSend(allocator, rpc, args, writer),
        .tx_payload => try handleTxPayload(allocator, args, writer),

        // Move commands
        .move_package => try handleMovePackage(allocator, rpc, args, writer),
        .move_module => try handleMoveModule(allocator, rpc, args, writer),
        .move_function => try handleMoveFunction(allocator, rpc, args, writer),

        // Object commands
        .object_get => try handleObjectGet(allocator, rpc, args, writer),
        .object_dynamic_fields => try handleObjectDynamicFields(allocator, rpc, args, writer),

        // RPC command
        .rpc => try handleRpc(allocator, rpc, args, writer),

        // Default handler for unimplemented commands
        else => try handleUnimplemented(writer, @tagName(command)),
    }
}

// ============================================================
// Help and Version Handlers
// ============================================================

fn handleHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: sui-zig-rpc-client [command] [options]
        \\
        \Commands:
        \  Wallet:
        \    wallet_create, wallet_import, wallet_use, wallet_accounts
        \    wallet_connect, wallet_disconnect, wallet_fund
        \  Account:
        \    account_list, account_info, account_balance, account_coins, account_objects
        \  Transaction:
        \    tx_simulate, tx_dry_run, tx_build, tx_send, tx_payload
        \  Move:
        \    move_package, move_module, move_function
        \  Object:
        \    object_get, object_dynamic_fields
        \  Other:
        \    rpc, help, version
        \\
    );
}

fn handleVersion(writer: anytype) !void {
    try writer.writeAll("sui-zig-rpc-client 0.1.2\n");
}

// ============================================================
// Wallet Handlers
// ============================================================

fn handleWalletCreate(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    // Generate a mock key for now
    const mock_key = "mock-private-key";
    try wallet.runWalletCreateOrImport(allocator, args, writer, "created", mock_key);
}

fn handleWalletImport(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    const raw_key = args.wallet_private_key orelse return error.InvalidCli;
    try wallet.runWalletCreateOrImport(allocator, args, writer, "imported", raw_key);
}

// ============================================================
// Account Handlers
// ============================================================

fn handleAccountBalance(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = rpc;
    const selector = args.account_selector orelse return error.InvalidCli;

    // Query balance (placeholder)
    const balance = try account.getAccountBalance(allocator, selector);

    if (args.account_balance_json) {
        try writer.print("{{\"address\":\"{s}\",\"balance\":{d}}}\n", .{ selector, balance });
    } else {
        try writer.print("Address: {s}, Balance: {d}\n", .{ selector, balance });
    }
}

// ============================================================
// Transaction Handlers
// ============================================================

fn handleTxSimulate(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Transaction simulation (placeholder)\n");
}

fn handleTxDryRun(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Transaction dry-run (placeholder)\n");
}

fn handleTxBuild(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Transaction build (placeholder)\n");
}

fn handleTxSend(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Transaction send (placeholder)\n");
}

fn handleTxPayload(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
    const sigs = args.signatures.items;

    const payload = try tx.buildExecutePayloadFromArgs(allocator, args, sigs, null);
    defer allocator.free(payload);

    try writer.print("{s}\n", .{payload});
}

// ============================================================
// Move Handlers
// ============================================================

fn handleMovePackage(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Move package (placeholder)\n");
}

fn handleMoveModule(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Move module (placeholder)\n");
}

fn handleMoveFunction(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Move function (placeholder)\n");
}

// ============================================================
// Object Handlers
// ============================================================

fn handleObjectGet(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Object get (placeholder)\n");
}

fn handleObjectDynamicFields(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("Object dynamic fields (placeholder)\n");
}

// ============================================================
// RPC Handler
// ============================================================

fn handleRpc(
    allocator: std.mem.Allocator,
    rpc: anytype,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = rpc;
    _ = args;
    try writer.writeAll("RPC call (placeholder)\n");
}

// ============================================================
// Default Handler
// ============================================================

fn handleUnimplemented(writer: anytype, command_name: []const u8) !void {
    try writer.print("Command '{s}' is not yet implemented in the new dispatch system\n", .{command_name});
}

// ============================================================
// Tests
// ============================================================

test "handleHelp outputs help text" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try handleHelp(output.writer());
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Usage:"));
}

test "handleVersion outputs version" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try handleVersion(output.writer());
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sui-zig-rpc-client"));
}

test "handleUnimplemented outputs message" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try handleUnimplemented(output.writer(), "test_command");
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "test_command"));
}
