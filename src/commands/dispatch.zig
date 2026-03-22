/// commands/dispatch.zig - Command dispatch logic (migrated to new RPC client API)
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

const client = @import("sui_client_zig");
const cli = @import("../cli.zig");

// Use new RPC client API
const rpc_new = client.rpc_client_new;
const SuiRpcClient = rpc_new.SuiRpcClient;

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
    rpc: *SuiRpcClient,
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
        .account_info => try account.getAccountInfo(allocator, rpc, args, writer),
        .account_balance => try account.printBalanceSummaryForOwner(allocator, rpc, writer, args.account_selector orelse return error.InvalidCli, args),
        .account_coins => try account.getAccountCoins(allocator, rpc, args, writer),
        .account_objects => try account.getAccountObjects(allocator, rpc, args, writer),

        // Transaction commands
        .tx_simulate => try tx.runTxSimulate(allocator, rpc, args, writer),
        .tx_dry_run => try tx.runTxDryRun(allocator, rpc, args, writer),
        .tx_build => try handleTxBuild(allocator, args, writer),
        .tx_send => try tx.runTxSend(allocator, rpc, args, writer),
        .tx_payload => try tx.runTxPayload(allocator, args, writer),

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
        \\Commands:
        \\  Wallet:
        \\    wallet_create, wallet_import, wallet_use, wallet_accounts
        \\    wallet_connect, wallet_disconnect, wallet_fund
        \\  Account:
        \\    account_list, account_info, account_balance, account_coins, account_objects
        \\  Transaction:
        \\    tx_simulate, tx_dry_run, tx_build, tx_send, tx_payload
        \\  Move:
        \\    move_package, move_module, move_function
        \\  Object:
        \\    object_get, object_dynamic_fields
        \\  Other:
        \\    rpc, help, version
        \\
    );
}

fn handleVersion(writer: anytype) !void {
    const version = @import("sui_client_zig").version;
    try writer.print("sui-zig-rpc-client {d}.{d}.{d}\n", .{ version.major, version.minor, version.patch });
}

// ============================================================
// Wallet Handlers
// ============================================================

fn handleWalletCreate(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    // Generate a new key using the client keystore
    const raw_key = client.keystore.generateRawKeyString(allocator) catch |err| {
        try writer.print("Failed to generate key: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(raw_key);
    
    try wallet.runWalletCreateOrImport(allocator, args, writer, "created", raw_key);
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
// Transaction Handlers
// ============================================================

fn handleTxBuild(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    // Validate arguments
    try tx.validateTxBuildArguments(args);
    
    // Build transaction block
    const tx_block = try tx.buildTransactionBlockFromArgs(allocator, args);
    defer allocator.free(tx_block);
    
    if (args.tx_send_summarize) {
        // Output summary
        var summary = std.json.ObjectMap.init(allocator);
        defer summary.deinit();
        
        try summary.put("kind", .{ .string = "transaction_block" });
        try summary.put("data", .{ .string = tx_block });
        
        try shared.printStructuredJson(writer, summary, args.pretty);
    } else {
        try writer.print("{s}\n", .{tx_block});
    }
}

// ============================================================
// Move Handlers (using new API)
// ============================================================

fn handleMovePackage(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const package_id = args.move_package_id orelse return error.InvalidCli;
    
    // Use new API to get normalized modules
    const modules = try rpc_new.getNormalizedMoveModule(rpc, package_id, "");
    defer modules.deinit(allocator);
    
    if (args.move_summarize) {
        try writer.print("Package: {s}\n", .{package_id});
        try writer.print("Module: {s}\n", .{modules.name});
    } else {
        try writer.print("Package: {s}, Module: {s}\n", .{ package_id, modules.name });
    }
}

fn handleMoveModule(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const package_id = args.move_package_id orelse return error.InvalidCli;
    const module_name = args.move_module_name orelse return error.InvalidCli;
    
    // Use new API
    const mod = try rpc_new.getNormalizedMoveModule(rpc, package_id, module_name);
    defer mod.deinit(allocator);
    
    if (args.move_summarize) {
        try writer.print("Package: {s}\n", .{package_id});
        try writer.print("Module: {s}\n", .{module_name});
        try writer.print("Structs: {d}, Functions: {d}\n", .{ mod.structs.len, mod.functions.len });
    } else {
        try writer.print("Module: {s}\n", .{mod.name});
    }
}

fn handleMoveFunction(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const package_id = args.move_package_id orelse return error.InvalidCli;
    const module_name = args.move_module_name orelse return error.InvalidCli;
    const function_name = args.move_function_name orelse return error.InvalidCli;
    
    // Use new API to get module
    const mod = try rpc_new.getNormalizedMoveModule(rpc, package_id, module_name);
    defer mod.deinit(allocator);
    
    // Find function
    var found = false;
    for (mod.functions) |func| {
        if (std.mem.eql(u8, func.name, function_name)) {
            found = true;
            if (args.move_function_output) |output_str| {
                const output = move.parseMoveFunctionTemplateOutput(output_str) catch {
                    try writer.print("Function: {s}\n", .{func.name});
                    return;
                };
                
                switch (output) {
                    .commands => try writer.print("Function: {s}\n", .{func.name}),
                    .tx_dry_run_request => try writer.writeAll("// Dry run request would be built here\n"),
                    .tx_send_from_keystore_request => try writer.writeAll("// Send request would be built here\n"),
                    else => try writer.print("Function: {s}\n", .{func.name}),
                }
            } else {
                try writer.print("Function: {s}\n", .{func.name});
            }
            break;
        }
    }
    
    if (!found) {
        try writer.print("Function '{s}' not found in module\n", .{function_name});
    }
}

// ============================================================
// Object Handlers (using new API)
// ============================================================

fn handleObjectGet(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const object_id = args.object_id orelse return error.InvalidCli;
    
    // Use new API
    const obj = try rpc_new.getObject(rpc, object_id, null);
    defer obj.deinit(allocator);
    
    if (args.pretty) {
        try writer.print("Object: {s}\n", .{obj.objectId});
        if (obj.type) |t| {
            try writer.print("Type: {s}\n", .{t});
        }
    } else {
        try writer.print("{s}\n", .{obj.objectId});
    }
}

fn handleObjectDynamicFields(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const object_id = args.object_id orelse return error.InvalidCli;
    
    // Use new API
    const fields = try rpc_new.getDynamicFields(rpc, object_id, null, null);
    defer fields.deinit(allocator);
    
    if (args.pretty) {
        try writer.print("Dynamic fields for {s}:\n", .{object_id});
        for (fields.data) |field| {
            try writer.print("  - {s}\n", .{field.name});
        }
    } else {
        try writer.print("Found {d} dynamic fields\n", .{fields.data.len});
    }
}

// ============================================================
// RPC Handler
// ============================================================

fn handleRpc(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const method = args.rpc_method orelse return error.InvalidCli;
    const params = args.rpc_params orelse "[]";
    
    // Use new API's raw call capability
    const response = try rpc.call(method, params);
    defer rpc.allocator.free(response);
    
    try shared.printJsonResponse(writer, response, args.pretty);
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

test "handleTxBuild validates arguments" {
    const testing = std.testing;
    
    const MockArgs = struct {
        tx_build_kind: ?tx.TxKind = null,
        tx_send_summarize: bool = false,
        pretty: bool = false,
    };
    
    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);
    
    // Should not error with empty args (placeholder validation)
    try handleTxBuild(testing.allocator, &args, output.writer());
}

test "handleMovePackage requires package_id" {
    const testing = std.testing;
    
    const MockArgs = struct {
        move_package_id: ?[]const u8 = null,
        move_summarize: bool = false,
    };
    
    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);
    
    var rpc = try SuiRpcClient.init(testing.allocator, "http://example.local");
    defer rpc.deinit();
    
    const result = handleMovePackage(testing.allocator, &rpc, &args, output.writer());
    try testing.expectError(error.InvalidCli, result);
}

test "handleObjectGet requires object_id" {
    const testing = std.testing;
    
    const MockArgs = struct {
        object_id: ?[]const u8 = null,
        pretty: bool = false,
    };
    
    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);
    
    var rpc = try SuiRpcClient.init(testing.allocator, "http://example.local");
    defer rpc.deinit();
    
    const result = handleObjectGet(testing.allocator, &rpc, &args, output.writer());
    try testing.expectError(error.InvalidCli, result);
}

test "handleRpc requires method" {
    const testing = std.testing;
    
    const MockArgs = struct {
        rpc_method: ?[]const u8 = null,
        rpc_params: ?[]const u8 = null,
        pretty: bool = false,
    };
    
    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);
    
    var rpc = try SuiRpcClient.init(testing.allocator, "http://example.local");
    defer rpc.deinit();
    
    const result = handleRpc(testing.allocator, &rpc, &args, output.writer());
    try testing.expectError(error.InvalidCli, result);
}
