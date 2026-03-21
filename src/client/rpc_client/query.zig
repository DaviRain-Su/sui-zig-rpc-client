/// client/rpc_client/query.zig - Query methods for RPC client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");
const constants = @import("constants.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Get balance for address
pub fn getBalance(
    client: *SuiRpcClient,
    address: []const u8,
    coin_type: ?[]const u8,
) !u64 {
    if (!utils.isValidAddress(address)) {
        return ClientError.InvalidResponse;
    }

    const params = if (coin_type) |ct|
        try std.fmt.allocPrint(client.allocator, "[\"{s}\",\"{s}\"]", .{ address, ct })
    else
        try std.fmt.allocPrint(client.allocator, "[\"{s}\"]", .{address});
    defer client.allocator.free(params);

    const response = try client.call("suix_getBalance", params);
    defer client.allocator.free(response);

    // Parse balance from response
    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("totalBalance")) |balance| {
            if (balance == .integer) {
                return @intCast(balance.integer);
            } else if (balance == .string) {
                return try std.fmt.parseInt(u64, balance.string, 10);
            }
        }
    }

    return 0;
}

/// Get all balances for address
pub fn getAllBalances(
    client: *SuiRpcClient,
    address: []const u8,
) ![]Balance {
    if (!utils.isValidAddress(address)) {
        return ClientError.InvalidResponse;
    }

    const params = try std.fmt.allocPrint(client.allocator, "[\"{s}\"]", .{address});
    defer client.allocator.free(params);

    const response = try client.call("suix_getAllBalances", params);
    defer client.allocator.free(response);

    // Parse balances from response
    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    var balances = std.ArrayList(Balance).init(client.allocator);
    errdefer balances.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result == .array) {
            for (result.array.items) |item| {
                if (item == .object) {
                    const balance = try parseBalance(client.allocator, item);
                    try balances.append(balance);
                }
            }
        }
    }

    return balances.toOwnedSlice();
}

/// Balance structure
pub const Balance = struct {
    coin_type: []const u8,
    coin_object_count: u64,
    total_balance: u64,
    locked_balance: ?u64,

    pub fn deinit(self: *Balance, allocator: std.mem.Allocator) void {
        allocator.free(self.coin_type);
    }
};

/// Parse balance from JSON
fn parseBalance(allocator: std.mem.Allocator, value: std.json.Value) !Balance {
    const coin_type = value.object.get("coinType") orelse return ClientError.InvalidResponse;
    const coin_object_count = value.object.get("coinObjectCount") orelse return ClientError.InvalidResponse;
    const total_balance = value.object.get("totalBalance") orelse return ClientError.InvalidResponse;

    var locked_balance: ?u64 = null;
    if (value.object.get("lockedBalance")) |locked| {
        if (locked != .null) {
            locked_balance = if (locked == .integer)
                @intCast(locked.integer)
            else
                try std.fmt.parseInt(u64, locked.string, 10);
        }
    }

    return Balance{
        .coin_type = try allocator.dupe(u8, coin_type.string),
        .coin_object_count = if (coin_object_count == .integer)
            @intCast(coin_object_count.integer)
        else
            try std.fmt.parseInt(u64, coin_object_count.string, 10),
        .total_balance = if (total_balance == .integer)
            @intCast(total_balance.integer)
        else
            try std.fmt.parseInt(u64, total_balance.string, 10),
        .locked_balance = locked_balance,
    };
}

/// Get object
pub fn getObject(
    client: *SuiRpcClient,
    object_id: []const u8,
    options: ?ObjectDataOptions,
) !Object {
    if (!utils.isValidObjectId(object_id)) {
        return ClientError.InvalidResponse;
    }

    const params = if (options) |opts|
        try std.fmt.allocPrint(client.allocator, "[\"{s}\",{s}]", .{ object_id, opts.toJson() })
    else
        try std.fmt.allocPrint(client.allocator, "[\"{s}\"]", .{object_id});
    defer client.allocator.free(params);

    const response = try client.call("sui_getObject", params);
    defer client.allocator.free(response);

    // Parse object from response
    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseObject(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Object data options
pub const ObjectDataOptions = struct {
    show_type: bool = false,
    show_owner: bool = false,
    show_previous_transaction: bool = false,
    show_display: bool = false,
    show_content: bool = false,
    show_bcs: bool = false,
    show_storage_rebate: bool = false,

    pub fn toJson(self: ObjectDataOptions) []const u8 {
        var buf: [256]u8 = undefined;
        return std.fmt.bufPrint(
            &buf,
            "{{\"showType\":{},\"showOwner\":{},\"showPreviousTransaction\":{},\"showDisplay\":{},\"showContent\":{},\"showBcs\":{},\"showStorageRebate\":{}}}",
            .{
                self.show_type,
                self.show_owner,
                self.show_previous_transaction,
                self.show_display,
                self.show_content,
                self.show_bcs,
                self.show_storage_rebate,
            },
        ) catch "{}";
    }
};

/// Object structure
pub const Object = struct {
    object_id: []const u8,
    version: u64,
    digest: []const u8,
    type: ?[]const u8,
    owner: ?[]const u8,
    content: ?[]const u8,

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
        if (self.type) |t| allocator.free(t);
        if (self.owner) |o| allocator.free(o);
        if (self.content) |c| allocator.free(c);
    }
};

/// Parse object from JSON
fn parseObject(allocator: std.mem.Allocator, value: std.json.Value) !Object {
    const data = value.object.get("data") orelse return ClientError.InvalidResponse;

    const object_id = data.object.get("objectId") orelse return ClientError.InvalidResponse;
    const version = data.object.get("version") orelse return ClientError.InvalidResponse;
    const digest = data.object.get("digest") orelse return ClientError.InvalidResponse;

    var object_type: ?[]const u8 = null;
    if (data.object.get("type")) |t| {
        if (t == .string) {
            object_type = try allocator.dupe(u8, t.string);
        }
    }

    var owner: ?[]const u8 = null;
    if (value.object.get("owner")) |o| {
        owner = try allocator.dupe(u8, "owner");
    }

    var content: ?[]const u8 = null;
    if (data.object.get("content")) |c| {
        content = try std.json.stringifyAlloc(allocator, c, .{});
    }

    return Object{
        .object_id = try allocator.dupe(u8, object_id.string),
        .version = if (version == .integer)
            @intCast(version.integer)
        else
            try std.fmt.parseInt(u64, version.string, 10),
        .digest = try allocator.dupe(u8, digest.string),
        .type = object_type,
        .owner = owner,
        .content = content,
    };
}

/// Get reference gas price
pub fn getReferenceGasPrice(client: *SuiRpcClient) !u64 {
    const response = try client.call("suix_getReferenceGasPrice", "[]");
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result == .integer) {
            return @intCast(result.integer);
        } else if (result == .string) {
            return try std.fmt.parseInt(u64, result.string, 10);
        }
    }

    return ClientError.InvalidResponse;
}

/// Get dynamic fields
pub fn getDynamicFields(
    client: *SuiRpcClient,
    parent_object_id: []const u8,
    cursor: ?[]const u8,
    limit: ?u64,
) !DynamicFieldPage {
    if (!utils.isValidObjectId(parent_object_id)) {
        return ClientError.InvalidResponse;
    }

    var params_buf: [1024]u8 = undefined;
    const params = try std.fmt.bufPrint(
        &params_buf,
        "[\"{s}\",{s},{s}]",
        .{
            parent_object_id,
            if (cursor) |c| try std.fmt.bufPrint(&params_buf, "\"{s}\"", .{c}) else "null",
            if (limit) |l| try std.fmt.bufPrint(&params_buf, "{}", .{l}) else "null",
        },
    );

    const response = try client.call("suix_getDynamicFields", params);
    defer client.allocator.free(response);

    // Parse dynamic fields from response
    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseDynamicFieldPage(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Dynamic field page
pub const DynamicFieldPage = struct {
    data: []DynamicField,
    next_cursor: ?[]const u8,
    has_next_page: bool,

    pub fn deinit(self: *DynamicFieldPage, allocator: std.mem.Allocator) void {
        for (self.data) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.data);
        if (self.next_cursor) |cursor| allocator.free(cursor);
    }
};

/// Dynamic field structure
pub const DynamicField = struct {
    name: []const u8,
    type: []const u8,
    object_id: []const u8,
    version: u64,
    digest: []const u8,

    pub fn deinit(self: *DynamicField, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.type);
        allocator.free(self.object_id);
        allocator.free(self.digest);
    }
};

/// Parse dynamic field page from JSON
fn parseDynamicFieldPage(allocator: std.mem.Allocator, value: std.json.Value) !DynamicFieldPage {
    const data = value.object.get("data") orelse return ClientError.InvalidResponse;

    var fields = std.ArrayList(DynamicField).init(allocator);
    errdefer fields.deinit();

    if (data == .array) {
        for (data.array.items) |item| {
            const field = try parseDynamicField(allocator, item);
            try fields.append(field);
        }
    }

    var next_cursor: ?[]const u8 = null;
    if (value.object.get("nextCursor")) |cursor| {
        if (cursor == .string) {
            next_cursor = try allocator.dupe(u8, cursor.string);
        }
    }

    const has_next_page = if (value.object.get("hasNextPage")) |has|
        has == .bool and has.bool
    else
        false;

    return DynamicFieldPage{
        .data = try fields.toOwnedSlice(),
        .next_cursor = next_cursor,
        .has_next_page = has_next_page,
    };
}

/// Parse dynamic field from JSON
fn parseDynamicField(allocator: std.mem.Allocator, value: std.json.Value) !DynamicField {
    const name = value.object.get("name") orelse return ClientError.InvalidResponse;
    const object_type = value.object.get("type") orelse return ClientError.InvalidResponse;
    const object_id = value.object.get("objectId") orelse return ClientError.InvalidResponse;
    const version = value.object.get("version") orelse return ClientError.InvalidResponse;
    const digest = value.object.get("digest") orelse return ClientError.InvalidResponse;

    return DynamicField{
        .name = try std.json.stringifyAlloc(allocator, name, .{}),
        .type = try allocator.dupe(u8, object_type.string),
        .object_id = try allocator.dupe(u8, object_id.string),
        .version = if (version == .integer)
            @intCast(version.integer)
        else
            try std.fmt.parseInt(u64, version.string, 10),
        .digest = try allocator.dupe(u8, digest.string),
    };
}

// ============================================================
// Tests
// ============================================================

test "ObjectDataOptions toJson" {
    const testing = std.testing;

    const opts = ObjectDataOptions{
        .show_type = true,
        .show_content = true,
    };

    const json = opts.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "showType"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "true"));
}

test "Balance structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var balance = Balance{
        .coin_type = try allocator.dupe(u8, "0x2::sui::SUI"),
        .coin_object_count = 5,
        .total_balance = 1_000_000_000,
        .locked_balance = null,
    };
    defer balance.deinit(allocator);

    try testing.expectEqualStrings("0x2::sui::SUI", balance.coin_type);
    try testing.expectEqual(@as(u64, 5), balance.coin_object_count);
}

test "Object structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var object = Object{
        .object_id = try allocator.dupe(u8, "0x123"),
        .version = 1,
        .digest = try allocator.dupe(u8, "abc"),
        .type = try allocator.dupe(u8, "0x2::coin::Coin"),
        .owner = null,
        .content = null,
    };
    defer object.deinit(allocator);

    try testing.expectEqualStrings("0x123", object.object_id);
    try testing.expectEqual(@as(u64, 1), object.version);
}

test "DynamicField structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var field = DynamicField{
        .name = try allocator.dupe(u8, "\"key\""),
        .type = try allocator.dupe(u8, "0x2::dynamic_field::Field"),
        .object_id = try allocator.dupe(u8, "0x456"),
        .version = 1,
        .digest = try allocator.dupe(u8, "def"),
    };
    defer field.deinit(allocator);

    try testing.expectEqualStrings("0x456", field.object_id);
}

test "DynamicFieldPage structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const fields = try allocator.alloc(DynamicField, 2);
    fields[0] = DynamicField{
        .name = try allocator.dupe(u8, "\"key1\""),
        .type = try allocator.dupe(u8, "type1"),
        .object_id = try allocator.dupe(u8, "0x1"),
        .version = 1,
        .digest = try allocator.dupe(u8, "a"),
    };
    fields[1] = DynamicField{
        .name = try allocator.dupe(u8, "\"key2\""),
        .type = try allocator.dupe(u8, "type2"),
        .object_id = try allocator.dupe(u8, "0x2"),
        .version = 1,
        .digest = try allocator.dupe(u8, "b"),
    };

    var page = DynamicFieldPage{
        .data = fields,
        .next_cursor = try allocator.dupe(u8, "cursor"),
        .has_next_page = true,
    };
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), page.data.len);
    try testing.expect(page.has_next_page);
}
