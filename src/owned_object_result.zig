const std = @import("std");

pub const OwnedObjectEntryStatus = enum {
    found,
    failed,
};

pub const OwnedObjectEntry = struct {
    status: OwnedObjectEntryStatus,
    object_id: ?[]u8 = null,
    version: ?u64 = null,
    digest: ?[]u8 = null,
    type_name: ?[]u8 = null,
    owner_kind: ?[]u8 = null,
    owner_value: ?[]u8 = null,
    previous_transaction: ?[]u8 = null,
    storage_rebate: ?u64 = null,
    error_message: ?[]u8 = null,

    pub fn deinit(self: *OwnedObjectEntry, allocator: std.mem.Allocator) void {
        if (self.object_id) |value| allocator.free(value);
        if (self.digest) |value| allocator.free(value);
        if (self.type_name) |value| allocator.free(value);
        if (self.owner_kind) |value| allocator.free(value);
        if (self.owner_value) |value| allocator.free(value);
        if (self.previous_transaction) |value| allocator.free(value);
        if (self.error_message) |value| allocator.free(value);
    }

    pub fn clone(self: OwnedObjectEntry, allocator: std.mem.Allocator) !OwnedObjectEntry {
        return .{
            .status = self.status,
            .object_id = if (self.object_id) |value| try allocator.dupe(u8, value) else null,
            .version = self.version,
            .digest = if (self.digest) |value| try allocator.dupe(u8, value) else null,
            .type_name = if (self.type_name) |value| try allocator.dupe(u8, value) else null,
            .owner_kind = if (self.owner_kind) |value| try allocator.dupe(u8, value) else null,
            .owner_value = if (self.owner_value) |value| try allocator.dupe(u8, value) else null,
            .previous_transaction = if (self.previous_transaction) |value| try allocator.dupe(u8, value) else null,
            .storage_rebate = self.storage_rebate,
            .error_message = if (self.error_message) |value| try allocator.dupe(u8, value) else null,
        };
    }
};

pub const OwnedObjectPage = struct {
    entries: []OwnedObjectEntry,
    next_cursor: ?[]u8 = null,
    has_next_page: bool = false,

    pub fn deinit(self: *OwnedObjectPage, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
        if (self.next_cursor) |value| allocator.free(value);
    }

    pub fn selectFirstFoundIndex(self: *const OwnedObjectPage) ?usize {
        for (self.entries, 0..) |entry, index| {
            if (entry.status == .found and entry.object_id != null) return index;
        }
        return null;
    }
};

fn parseOptionalU64(value: ?std.json.Value) ?u64 {
    const current = value orelse return null;
    return switch (current) {
        .integer => |integer| if (integer >= 0) @intCast(integer) else null,
        .string => |text| std.fmt.parseInt(u64, text, 10) catch null,
        else => null,
    };
}

fn dupeOptionalStringField(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) !?[]u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return try allocator.dupe(u8, value.string);
}

fn extractRootResult(value: std.json.Value) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get("result") orelse value;
}

fn stringifyJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
}

fn extractOwner(
    allocator: std.mem.Allocator,
    owner_value: ?std.json.Value,
) !struct { kind: ?[]u8, value: ?[]u8 } {
    const owner = owner_value orelse return .{ .kind = null, .value = null };
    if (owner != .object) {
        return .{
            .kind = null,
            .value = try stringifyJsonValue(allocator, owner),
        };
    }

    if (owner.object.get("AddressOwner")) |value| {
        return .{
            .kind = try allocator.dupe(u8, "address_owner"),
            .value = if (value == .string) try allocator.dupe(u8, value.string) else try stringifyJsonValue(allocator, value),
        };
    }
    if (owner.object.get("ObjectOwner")) |value| {
        return .{
            .kind = try allocator.dupe(u8, "object_owner"),
            .value = if (value == .string) try allocator.dupe(u8, value.string) else try stringifyJsonValue(allocator, value),
        };
    }
    if (owner.object.get("Shared")) |value| {
        return .{
            .kind = try allocator.dupe(u8, "shared"),
            .value = try stringifyJsonValue(allocator, value),
        };
    }
    if (owner.object.get("Immutable") != null) {
        return .{
            .kind = try allocator.dupe(u8, "immutable"),
            .value = null,
        };
    }

    return .{
        .kind = null,
        .value = try stringifyJsonValue(allocator, owner),
    };
}

pub fn extractOwnedObjectPage(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedObjectPage {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const data = result.object.get("data") orelse return error.InvalidResponse;
    if (data != .array) return error.InvalidResponse;

    const entries = try allocator.alloc(OwnedObjectEntry, data.array.items.len);
    errdefer allocator.free(entries);

    for (data.array.items, 0..) |item, index| {
        if (item != .object) return error.InvalidResponse;

        if (item.object.get("error")) |error_value| {
            entries[index] = .{
                .status = .failed,
                .error_message = try stringifyJsonValue(allocator, error_value),
            };
            continue;
        }

        const resolved = if (item.object.get("data")) |nested_data| nested_data else item;
        if (resolved != .object) return error.InvalidResponse;

        const owner = try extractOwner(allocator, resolved.object.get("owner"));
        entries[index] = .{
            .status = .found,
            .object_id = try dupeOptionalStringField(allocator, resolved.object, "objectId"),
            .version = parseOptionalU64(resolved.object.get("version")),
            .digest = try dupeOptionalStringField(allocator, resolved.object, "digest"),
            .type_name = try dupeOptionalStringField(allocator, resolved.object, "type"),
            .owner_kind = owner.kind,
            .owner_value = owner.value,
            .previous_transaction = try dupeOptionalStringField(allocator, resolved.object, "previousTransaction"),
            .storage_rebate = parseOptionalU64(resolved.object.get("storageRebate")),
        };
    }

    return .{
        .entries = entries,
        .next_cursor = try dupeOptionalStringField(allocator, result.object, "nextCursor"),
        .has_next_page = if (result.object.get("hasNextPage")) |value|
            switch (value) {
                .bool => |flag| flag,
                else => false,
            }
        else
            false,
    };
}

test "extractOwnedObjectPage parses owned-object pagination envelopes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var page = try extractOwnedObjectPage(allocator,
        \\{"result":{"data":[{"data":{"objectId":"0xobject","version":"7","digest":"digest-1","type":"0x2::coin::Coin<0x2::sui::SUI>","owner":{"AddressOwner":"0xowner"},"previousTransaction":"0xprev","storageRebate":"42"}}],"nextCursor":"cursor-2","hasNextPage":true}}
    );
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.entries.len);
    try testing.expectEqual(OwnedObjectEntryStatus.found, page.entries[0].status);
    try testing.expectEqualStrings("0xobject", page.entries[0].object_id.?);
    try testing.expectEqual(@as(?u64, 7), page.entries[0].version);
    try testing.expectEqualStrings("0x2::coin::Coin<0x2::sui::SUI>", page.entries[0].type_name.?);
    try testing.expectEqualStrings("address_owner", page.entries[0].owner_kind.?);
    try testing.expectEqualStrings("0xowner", page.entries[0].owner_value.?);
    try testing.expectEqualStrings("cursor-2", page.next_cursor.?);
    try testing.expect(page.has_next_page);
}

test "extractOwnedObjectPage keeps item-level errors" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var page = try extractOwnedObjectPage(allocator,
        \\{"result":{"data":[{"error":{"code":-1,"message":"boom"}}],"hasNextPage":false}}
    );
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.entries.len);
    try testing.expectEqual(OwnedObjectEntryStatus.failed, page.entries[0].status);
    try testing.expect(std.mem.indexOf(u8, page.entries[0].error_message.?, "\"boom\"") != null);
}

test "OwnedObjectPage selects the first found entry" {
    const testing = std.testing;
    var object_id_1 = [_]u8{ '0', 'x', 'o', 'b', 'j', 'e', 'c', 't', '-', '1' };
    var object_id_2 = [_]u8{ '0', 'x', 'o', 'b', 'j', 'e', 'c', 't', '-', '2' };
    var entries = [_]OwnedObjectEntry{
        .{ .status = .failed, .error_message = null },
        .{ .status = .found, .object_id = object_id_1[0..] },
        .{ .status = .found, .object_id = object_id_2[0..] },
    };

    const page = OwnedObjectPage{
        .entries = entries[0..],
    };

    try testing.expectEqual(@as(?usize, 1), page.selectFirstFoundIndex());
}
