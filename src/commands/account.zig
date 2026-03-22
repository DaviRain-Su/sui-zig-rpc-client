/// commands/account.zig - Account commands (migrated to new RPC client API)
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

const client = @import("sui_client_zig");
const wallet_state = @import("../wallet_state.zig");
const cli = @import("../cli.zig");

// Use new RPC client API
const rpc_new = client.rpc_client_new;
const SuiRpcClient = rpc_new.SuiRpcClient;

/// Account information
pub const AccountInfo = struct {
    address: []const u8,
    balance: u64,
    object_count: u64,

    pub fn deinit(self: *AccountInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
    }
};

/// Coin information
pub const CoinInfo = struct {
    coin_type: []const u8,
    balance: u64,
    object_id: []const u8,

    pub fn deinit(self: *CoinInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.coin_type);
        allocator.free(self.object_id);
    }
};

/// Object information
pub const ObjectInfo = struct {
    object_id: []const u8,
    object_type: ?[]const u8,
    version: u64,

    pub fn deinit(self: *ObjectInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        if (self.object_type) |t| allocator.free(t);
    }
};

/// Resolve wallet owner from args
fn resolveWalletOwner(
    allocator: std.mem.Allocator,
    args: anytype,
) !struct { owner: []const u8, owned: ?[]u8 } {
    const selector = args.account_selector orelse {
        // Try to get from wallet state
        const state = wallet_state.readDefaultWalletState(allocator) catch null;
        defer if (state) |s| allocator.free(s);
        
        if (state) |s| {
            const owned = try allocator.dupe(u8, s);
            return .{ .owner = owned, .owned = owned };
        }
        
        return error.InvalidCli;
    };
    
    if (std.mem.startsWith(u8, selector, "0x")) {
        const owned = try allocator.dupe(u8, selector);
        return .{ .owner = owned, .owned = owned };
    }
    
    // Resolve by alias
    const address = try client.keystore.resolveAddressBySelector(allocator, selector) orelse return error.InvalidCli;
    return .{ .owner = address, .owned = address };
}

/// List accounts from keystore
pub fn listAccounts(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    const keystore_path = try client.keystore.resolveDefaultSuiKeystorePath(allocator);
    defer if (keystore_path) |p| allocator.free(p);
    
    if (keystore_path) |path| {
        const contents = readOptionalFileAtPathAlloc(allocator, path, 4 * 1024 * 1024) catch null;
        defer if (contents) |c| allocator.free(c);
        
        if (args.account_info_json) {
            try writer.writeAll("{\"accounts\":[");
            if (contents) |c| {
                // Parse and output accounts
                const parsed = std.json.parseFromSlice(std.json.Value, allocator, c, .{}) catch null;
                defer if (parsed) |p| p.deinit();
                
                if (parsed) |p| {
                    for (p.value.array.items, 0..) |item, i| {
                        if (i > 0) try writer.writeAll(",");
                        if (item.object.get("address")) |addr| {
                            try writer.print("\"{s}\"", .{addr.string});
                        }
                    }
                }
            }
            try writer.writeAll("]}\n");
        } else {
            try writer.writeAll("Accounts:\n");
            if (contents) |c| {
                const parsed = std.json.parseFromSlice(std.json.Value, allocator, c, .{}) catch null;
                defer if (parsed) |p| p.deinit();
                
                if (parsed) |p| {
                    for (p.value.array.items) |item| {
                        if (item.object.get("address")) |addr| {
                            try writer.print("  - {s}", .{addr.string});
                            if (item.object.get("alias")) |alias| {
                                try writer.print(" ({s})", .{alias.string});
                            }
                            try writer.writeAll("\n");
                        }
                    }
                }
            }
        }
    } else {
        try writer.writeAll("No keystore found\n");
    }
}

/// Get account info with RPC
pub fn getAccountInfo(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const resolved = try resolveWalletOwner(allocator, args);
    defer if (resolved.owned) |o| allocator.free(o);
    
    if (args.account_info_json) {
        try writer.print("{{\"address\":\"{s}\"}}\n", .{resolved.owner});
    } else {
        try writer.print("Address: {s}\n", .{resolved.owner});
    }
}

/// Get account balance via RPC (using new API)
pub fn getAccountBalance(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    address: []const u8,
) !u64 {
    // Use new API
    const balance = try rpc_new.getBalance(rpc, address, null);
    defer balance.deinit(allocator);
    
    return balance.totalBalance;
}

/// Print balance summary for owner (using new API)
pub fn printBalanceSummaryForOwner(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    writer: anytype,
    owner: []const u8,
    args: anytype,
) !void {
    const balance = try getAccountBalance(allocator, rpc, owner);
    
    if (args.account_info_json) {
        try writer.print("{{\"address\":\"{s}\",\"balance\":{d}}}\n", .{ owner, balance });
    } else {
        try writer.print("Address: {s}\n", .{owner});
        try writer.print("Balance: {d} MIST ({d:.9} SUI)\n", .{ balance, @as(f64, @floatFromInt(balance)) / 1_000_000_000.0 });
    }
}

/// Get account coins via RPC (using new API)
pub fn getAccountCoins(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const resolved = try resolveWalletOwner(allocator, args);
    defer if (resolved.owned) |o| allocator.free(o);
    
    // Use new API - get all coins
    const coins = try rpc_new.getAllCoins(rpc, resolved.owner, null, null);
    defer coins.deinit(allocator);
    
    if (args.account_info_json) {
        // Output as JSON
        try writer.writeAll("{\"coins\":[");
        for (coins.data, 0..) |coin, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"coinType\":\"{s}\",\"balance\":{d},\"objectId\":\"{s}\"}}", .{
                coin.coin_type,
                coin.balance,
                coin.object_id,
            });
        }
        try writer.writeAll("]}\n");
    } else {
        try writer.print("Coins for {s}:\n", .{resolved.owner});
        for (coins.data) |coin| {
            try writer.print("  - {s}: {d}\n", .{ coin.coin_type, coin.balance });
        }
    }
}

/// Get account objects via RPC (using new API)
pub fn getAccountObjects(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    args: anytype,
    writer: anytype,
) !void {
    const resolved = try resolveWalletOwner(allocator, args);
    defer if (resolved.owned) |o| allocator.free(o);
    
    // Use new API
    const objects = try rpc_new.getOwnedObjects(rpc, resolved.owner, null);
    defer objects.deinit(allocator);
    
    if (args.account_info_json) {
        // Output as JSON
        try writer.writeAll("{\"objects\":[");
        for (objects.data, 0..) |obj, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"objectId\":\"{s}\"", .{obj.objectId});
            if (obj.type) |t| {
                try writer.print(",\"type\":\"{s}\"", .{t});
            }
            try writer.writeAll("}");
        }
        try writer.writeAll("]}\n");
    } else {
        try writer.print("Objects for {s}:\n", .{resolved.owner});
        for (objects.data) |obj| {
            try writer.print("  - {s}", .{obj.objectId});
            if (obj.type) |t| {
                try writer.print(" ({s})", .{t});
            }
            try writer.writeAll("\n");
        }
    }
}

/// Read optional file at path
fn readOptionalFileAtPathAlloc(allocator: std.mem.Allocator, path: []const u8, max_size: usize) !?[]const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const size = try file.getEndPos();
    if (size > max_size) return error.FileTooBig;

    const contents = try allocator.alloc(u8, size);
    errdefer allocator.free(contents);

    const read_size = try file.readAll(contents);
    if (read_size != size) return error.UnexpectedEof;

    return contents;
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

test "getAccountInfo requires selector or wallet state" {
    const testing = std.testing;

    const MockArgs = struct {
        account_selector: ?[]const u8 = null,
        account_info_json: bool = false,
    };

    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    // Use new API client
    var rpc = try SuiRpcClient.init(testing.allocator, "http://example.local");
    defer rpc.deinit();

    // Should fail without selector or wallet state
    const result = getAccountInfo(testing.allocator, &rpc, &args, output.writer());
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

test "CoinInfo lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const coin_type = try allocator.dupe(u8, "0x2::sui::SUI");
    const object_id = try allocator.dupe(u8, "0xabc");
    var info = CoinInfo{
        .coin_type = coin_type,
        .balance = 1000,
        .object_id = object_id,
    };
    defer info.deinit(allocator);

    try testing.expectEqual(@as(u64, 1000), info.balance);
}

test "ObjectInfo lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const object_id = try allocator.dupe(u8, "0xobj");
    const object_type = try allocator.dupe(u8, "0x2::coin::Coin");
    var info = ObjectInfo{
        .object_id = object_id,
        .object_type = object_type,
        .version = 1,
    };
    defer info.deinit(allocator);

    try testing.expectEqual(@as(u64, 1), info.version);
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

test "formatAccountInfo non-pretty" {
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

    try formatAccountInfo(output.writer(), &info, false);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "0xabc,500,3"));
}
