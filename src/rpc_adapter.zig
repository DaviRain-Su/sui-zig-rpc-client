/// rpc_adapter.zig - Adapter to bridge old and new RPC client APIs
///
/// This module provides compatibility functions to help migrate from
/// old rpc_client to new rpc_client_new API.

const std = @import("std");

// Old API
const old_rpc = @import("client/rpc_client/client.zig");
// New API
const new_rpc = @import("client/rpc_client/root.zig");

/// Get balance using new API
pub fn getBalanceNew(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    address: []const u8,
) !u64 {
    var client = try new_rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const balance = try new_rpc.getBalance(&client, address, null);
    defer balance.deinit(allocator);

    return balance.totalBalance;
}

/// Get owned objects using new API
pub fn getOwnedObjectsNew(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    address: []const u8,
) ![][]const u8 {
    var client = try new_rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const objects = try new_rpc.getOwnedObjects(&client,
        address,
        null, // filter
    );
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
pub fn simulateTransactionNew(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    tx_bytes: []const u8,
) !bool {
    var client = try new_rpc.SuiRpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const result = try new_rpc.simulateTransaction(
        &client,
        tx_bytes,
        .{}, // options
    );
    defer result.deinit(allocator);

    return result.effects.status == .success;
}

// ============================================================
// Tests
// ============================================================

test "rpc_adapter module imports" {
    _ = getBalanceNew;
    _ = getOwnedObjectsNew;
    _ = simulateTransactionNew;
}
