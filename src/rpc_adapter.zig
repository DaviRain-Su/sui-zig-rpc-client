/// rpc_adapter.zig - Adapter for new RPC client API
///
/// This module provides compatibility functions using the new RPC client API.
/// All functions now use the new modular RPC client (rpc_client_new).

const std = @import("std");

// Use new API only
const rpc = @import("client/rpc_client/root.zig");

/// Get balance using new API
pub fn getBalance(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    address: []const u8,
) !u64 {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const balance = try rpc.getBalance(&client, address, null);
    defer balance.deinit(allocator);

    return balance.totalBalance;
}

/// Get all balances using new API
pub fn getAllBalances(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    address: []const u8,
) ![]rpc.Balance {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    return try rpc.getAllBalances(&client, address);
}

/// Get owned objects using new API
pub fn getOwnedObjects(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    address: []const u8,
) ![][]const u8 {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const objects = try rpc.getOwnedObjects(&client, address, null);
    defer objects.deinit(allocator);

    // Copy object IDs to result
    var result = try allocator.alloc([]const u8, objects.data.len);
    errdefer allocator.free(result);

    for (objects.data, 0..) |obj, i| {
        result[i] = try allocator.dupe(u8, obj.objectId);
    }

    return result;
}

/// Free object IDs array
pub fn freeObjectIds(allocator: std.mem.Allocator, ids: [][]const u8) void {
    for (ids) |id| {
        allocator.free(id);
    }
    allocator.free(ids);
}

/// Simulate transaction using new API
pub fn simulateTransaction(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    tx_bytes: []const u8,
) !bool {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const result = try rpc.simulateTransaction(
        &client,
        tx_bytes,
        .{}, // options
    );
    defer result.deinit(allocator);

    return result.effects.status == .success;
}

/// Execute transaction using new API
pub fn executeTransaction(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    tx_bytes: []const u8,
    signatures: []const []const u8,
) ![]const u8 {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const result = try rpc.executeTransaction(
        &client,
        tx_bytes,
        signatures,
        .{}, // options
    );
    defer result.deinit(allocator);

    // Return digest
    return try allocator.dupe(u8, result.digest);
}

/// Get object using new API
pub fn getObject(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    object_id: []const u8,
) !rpc.Object {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const options = rpc.ObjectDataOptions{
        .show_type = true,
        .show_content = true,
        .show_owner = true,
    };

    return try rpc.getObject(&client, object_id, options);
}

/// Get reference gas price using new API
pub fn getReferenceGasPrice(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
) !u64 {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    return try rpc.getReferenceGasPrice(&client);
}

/// Query events using new API
pub fn queryEvents(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    filter: rpc.EventFilter,
    limit: usize,
) !rpc.EventPage {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    return try rpc.queryEvents(&client, filter, null, limit, false);
}

/// Get normalized Move module using new API
pub fn getNormalizedMoveModule(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    package_id: []const u8,
    module_name: []const u8,
) !rpc.NormalizedMoveModule {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    return try rpc.getNormalizedMoveModule(&client, package_id, module_name);
}

// ============================================================
// Convenience wrappers
// ============================================================

/// Get SUI balance in SUI (not MIST)
pub fn getSuiBalance(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    address: []const u8,
) !f64 {
    const balance = try getBalance(allocator, rpc_url, address);
    return rpc.mistToSui(balance);
}

/// Check if an object exists
pub fn objectExists(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    object_id: []const u8,
) !bool {
    var client = try rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const options = rpc.ObjectDataOptions{ .show_type = false };
    const obj = rpc.getObject(&client, object_id, options) catch |err| {
        if (err == error.ObjectNotFound) return false;
        return err;
    };
    defer obj.deinit(allocator);

    return true;
}

// ============================================================
// Tests
// ============================================================

test "rpc_adapter module imports" {
    _ = getBalance;
    _ = getAllBalances;
    _ = getOwnedObjects;
    _ = simulateTransaction;
    _ = executeTransaction;
    _ = getObject;
    _ = getReferenceGasPrice;
    _ = queryEvents;
    _ = getNormalizedMoveModule;
    _ = getSuiBalance;
    _ = objectExists;
}

test "rpc_adapter re-exports work" {
    // Test that we can access all re-exported types
    _ = rpc.SuiRpcClient;
    _ = rpc.Balance;
    _ = rpc.Object;
    _ = rpc.EventFilter;
    _ = rpc.SimulationResult;
    _ = rpc.ExecutionResult;
    _ = rpc.NormalizedMoveModule;
    _ = rpc.ObjectDataOptions;

    // Test utility functions
    _ = rpc.mistToSui;
    _ = rpc.suiToMist;
    _ = rpc.isValidAddress;
}
