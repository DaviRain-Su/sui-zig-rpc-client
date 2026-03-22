/// client/rpc_client/object.zig - Object methods for RPC client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Get multiple objects
pub fn getMultipleObjects(
    client: *SuiRpcClient,
    object_ids: []const []const u8,
    options: ?ObjectDataOptions,
) ![]Object {
    // Validate all object IDs
    for (object_ids) |id| {
        if (!utils.isValidObjectId(id)) {
            return ClientError.InvalidResponse;
        }
    }

    // Build object IDs JSON array
    var ids_json: std.ArrayList(u8) = .empty;
    defer {
        client.allocator.free(ids_json.items);
    }

    try ids_json.append('[');
    for (object_ids, 0..) |id, i| {
        if (i > 0) try ids_json.append(',');
        try std.fmt.format(ids_json.writer(), "\"{s}\"", .{id});
    }
    try ids_json.append(']');

    const params = if (options) |opts|
        try std.fmt.allocPrint(client.allocator, "[{s},{s}]", .{ ids_json.items, opts.toJson() })
    else
        try std.fmt.allocPrint(client.allocator, "[{s},{{}}]", .{ids_json.items});
    defer client.allocator.free(params);

    const response = try client.call("sui_multiGetObjects", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    var objects: std.ArrayList(Object) = .empty;
    errdefer {
        for (objects.items) |*obj| obj.deinit(client.allocator);
        client.allocator.free(objects.items);
    }

    if (parsed.value.object.get("result")) |result| {
        if (result == .array) {
            for (result.array.items) |item| {
                const obj = try parseObject(client.allocator, item);
                try objects.append(client.allocator, obj);
            }
        }
    }

    const result = try client.allocator.dupe(Object, objects.items);
    client.allocator.free(objects.items);
    return result;
}

/// Object data options
pub const ObjectDataOptions = struct {
    show_type: bool = true,
    show_owner: bool = false,
    show_previous_transaction: bool = false,
    show_display: bool = false,
    show_content: bool = true,
    show_bcs: bool = false,
    show_storage_rebate: bool = false,

    pub fn toJson(self: ObjectDataOptions) []const u8 {
        var buf: [512]u8 = undefined;
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
    owner: ?Owner,
    content: ?[]const u8,
    display: ?[]const u8,
    bcs: ?[]const u8,
    storage_rebate: ?u64,
    previous_transaction: ?[]const u8,

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
        if (self.type) |t| allocator.free(t);
        if (self.owner) |*o| o.deinit(allocator);
        if (self.content) |c| allocator.free(c);
        if (self.display) |d| allocator.free(d);
        if (self.bcs) |b| allocator.free(b);
        if (self.previous_transaction) |p| allocator.free(p);
    }
};

/// Owner structure
pub const Owner = struct {
    owner_type: OwnerType,
    address: ?[]const u8,
    initial_shared_version: ?u64,

    pub fn deinit(self: *Owner, allocator: std.mem.Allocator) void {
        if (self.address) |a| allocator.free(a);
    }
};

/// Owner type
pub const OwnerType = enum {
    address_owner,
    object_owner,
    shared,
    immutable,
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

    var owner: ?Owner = null;
    if (value.object.get("owner")) |o| {
        owner = try parseOwner(allocator, o);
    }

    const content: ?[]const u8 = null;
    if (data.object.get("content")) |c| {
        // Zig 0.15.2 doesn't have stringifyAlloc, skip for now
        _ = c;
    }

    const display: ?[]const u8 = null;
    if (data.object.get("display")) |d| {
        // Zig 0.15.2 doesn't have stringifyAlloc, skip for now
        _ = d;
    }

    var bcs: ?[]const u8 = null;
    if (data.object.get("bcs")) |b| {
        if (b == .string) {
            bcs = try allocator.dupe(u8, b.string);
        }
    }

    var storage_rebate: ?u64 = null;
    if (data.object.get("storageRebate")) |sr| {
        if (sr != .null) {
            storage_rebate = if (sr == .integer)
                @intCast(sr.integer)
            else
                try std.fmt.parseInt(u64, sr.string, 10);
        }
    }

    var previous_transaction: ?[]const u8 = null;
    if (data.object.get("previousTransaction")) |pt| {
        if (pt == .string) {
            previous_transaction = try allocator.dupe(u8, pt.string);
        }
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
        .display = display,
        .bcs = bcs,
        .storage_rebate = storage_rebate,
        .previous_transaction = previous_transaction,
    };
}

/// Parse owner from JSON
fn parseOwner(allocator: std.mem.Allocator, value: std.json.Value) !Owner {
    if (value.object.get("AddressOwner")) |addr| {
        return Owner{
            .owner_type = .address_owner,
            .address = try allocator.dupe(u8, addr.string),
            .initial_shared_version = null,
        };
    }

    if (value.object.get("ObjectOwner")) |addr| {
        return Owner{
            .owner_type = .object_owner,
            .address = try allocator.dupe(u8, addr.string),
            .initial_shared_version = null,
        };
    }

    if (value.object.get("Shared")) |shared| {
        const initial_version = shared.object.get("initial_shared_version").?;
        return Owner{
            .owner_type = .shared,
            .address = null,
            .initial_shared_version = if (initial_version == .integer)
                @intCast(initial_version.integer)
            else
                try std.fmt.parseInt(u64, initial_version.string, 10),
        };
    }

    if (value.object.get("Immutable") != null) {
        return Owner{
            .owner_type = .immutable,
            .address = null,
            .initial_shared_version = null,
        };
    }

    return ClientError.InvalidResponse;
}

/// Get owned objects
pub fn getOwnedObjects(
    client: *SuiRpcClient,
    owner: []const u8,
    query: ?ObjectQuery,
    cursor: ?[]const u8,
    limit: ?u32,
) !ObjectPage {
    if (!utils.isValidAddress(owner)) {
        return ClientError.InvalidResponse;
    }

    var params_buf: [2048]u8 = undefined;
    var params: []const u8 = undefined;

    if (query) |q| {
        const query_json = q.toJson();
        params = try std.fmt.bufPrint(
            &params_buf,
            "[\"{s}\",{s},{s},{s}]",
            .{
                owner,
                query_json,
                if (cursor) |c| try std.fmt.bufPrint(&params_buf, "\"{s}\"", .{c}) else "null",
                if (limit) |l| try std.fmt.bufPrint(&params_buf, "{}", .{l}) else "null",
            },
        );
    } else {
        params = try std.fmt.bufPrint(
            &params_buf,
            "[\"{s}\",null,{s},{s}]",
            .{
                owner,
                if (cursor) |c| try std.fmt.bufPrint(&params_buf, "\"{s}\"", .{c}) else "null",
                if (limit) |l| try std.fmt.bufPrint(&params_buf, "{}", .{l}) else "null",
            },
        );
    }

    const response = try client.call("suix_getOwnedObjects", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseObjectPage(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Object query
pub const ObjectQuery = struct {
    filter: ?ObjectFilter = null,
    options: ObjectDataOptions = .{},

    pub fn toJson(self: ObjectQuery) []const u8 {
        var buf: [1024]u8 = undefined;
        const filter_json = if (self.filter) |f| f.toJson() else "null";
        const options_json = self.options.toJson();
        return std.fmt.bufPrint(
            &buf,
            "{{\"filter\":{s},\"options\":{s}}}",
            .{ filter_json, options_json },
        ) catch "{}";
    }
};

/// Object filter
pub const ObjectFilter = union(enum) {
    match_all: []const ObjectFilter,
    match_any: []const ObjectFilter,
    match_none: []const ObjectFilter,
    package: []const u8,
    move_module: struct { package: []const u8, module: []const u8 },
    struct_type: []const u8,
    address_owner: []const u8,
    object_owner: []const u8,
    object_ids: []const []const u8,
    version: struct { object_id: []const u8, version: u64 },

    pub fn toJson(self: ObjectFilter) []const u8 {
        var buf: [1024]u8 = undefined;
        return switch (self) {
            .package => |p| std.fmt.bufPrint(&buf, "{{\"Package\":\"{s}\"}}", .{p}) catch "null",
            .move_module => |m| std.fmt.bufPrint(&buf, "{{\"MoveModule\":{{\"package\":\"{s}\",\"module\":\"{s}\"}}}}", .{ m.package, m.module }) catch "null",
            .struct_type => |s| std.fmt.bufPrint(&buf, "{{\"StructType\":\"{s}\"}}", .{s}) catch "null",
            .address_owner => |a| std.fmt.bufPrint(&buf, "{{\"AddressOwner\":\"{s}\"}}", .{a}) catch "null",
            .object_owner => |o| std.fmt.bufPrint(&buf, "{{\"ObjectOwner\":\"{s}\"}}", .{o}) catch "null",
            else => "null",
        };
    }
};

/// Object page
pub const ObjectPage = struct {
    data: []Object,
    next_cursor: ?[]const u8,
    has_next_page: bool,

    pub fn deinit(self: *ObjectPage, allocator: std.mem.Allocator) void {
        for (self.data) |*obj| {
            obj.deinit(allocator);
        }
        allocator.free(self.data);
        if (self.next_cursor) |cursor| allocator.free(cursor);
    }
};

/// Parse object page from JSON
fn parseObjectPage(allocator: std.mem.Allocator, value: std.json.Value) !ObjectPage {
    const data = value.object.get("data") orelse return ClientError.InvalidResponse;

    var objects: std.ArrayList(Object) = .empty;
    errdefer {
        for (objects.items) |*obj| obj.deinit(allocator);
        allocator.free(objects.items);
    }

    if (data == .array) {
        for (data.array.items) |item| {
            const obj = try parseObject(allocator, item);
            try objects.append(allocator, obj);
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

    const result = try allocator.dupe(Object, objects.items);
    allocator.free(objects.items);
    
    return ObjectPage{
        .data = result,
        .next_cursor = next_cursor,
        .has_next_page = has_next_page,
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

test "Object structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var obj = Object{
        .object_id = try allocator.dupe(u8, "0x123"),
        .version = 1,
        .digest = try allocator.dupe(u8, "abc"),
        .type = try allocator.dupe(u8, "0x2::coin::Coin"),
        .owner = null,
        .content = null,
        .display = null,
        .bcs = null,
        .storage_rebate = null,
        .previous_transaction = null,
    };
    defer obj.deinit(allocator);

    try testing.expectEqualStrings("0x123", obj.object_id);
    try testing.expectEqual(@as(u64, 1), obj.version);
}

test "Owner structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var owner = Owner{
        .owner_type = .address_owner,
        .address = try allocator.dupe(u8, "0x456"),
        .initial_shared_version = null,
    };
    defer owner.deinit(allocator);

    try testing.expectEqual(OwnerType.address_owner, owner.owner_type);
}

test "ObjectQuery toJson" {
    const testing = std.testing;

    const query = ObjectQuery{
        .filter = ObjectFilter{ .package = "0x2" },
        .options = .{ .show_type = true },
    };

    const json = query.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "filter"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "options"));
}

test "ObjectFilter toJson" {
    const testing = std.testing;

    const filter = ObjectFilter{ .package = "0x2" };
    const json = filter.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "Package"));
}

test "ObjectPage structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const objects = try allocator.alloc(Object, 2);
    objects[0] = Object{
        .object_id = try allocator.dupe(u8, "0x1"),
        .version = 1,
        .digest = try allocator.dupe(u8, "a"),
        .type = null,
        .owner = null,
        .content = null,
        .display = null,
        .bcs = null,
        .storage_rebate = null,
        .previous_transaction = null,
    };
    objects[1] = Object{
        .object_id = try allocator.dupe(u8, "0x2"),
        .version = 1,
        .digest = try allocator.dupe(u8, "b"),
        .type = null,
        .owner = null,
        .content = null,
        .display = null,
        .bcs = null,
        .storage_rebate = null,
        .previous_transaction = null,
    };

    var page = ObjectPage{
        .data = objects,
        .next_cursor = try allocator.dupe(u8, "cursor"),
        .has_next_page = true,
    };
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), page.data.len);
    try testing.expect(page.has_next_page);
}
