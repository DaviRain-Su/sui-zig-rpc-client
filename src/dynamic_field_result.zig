const std = @import("std");

pub const OwnedDynamicFieldEntry = struct {
    name_type: ?[]u8 = null,
    name_value_json: ?[]u8 = null,
    bcs_name: ?[]u8 = null,
    field_kind: ?[]u8 = null,
    object_type: ?[]u8 = null,
    object_id: ?[]u8 = null,
    version: ?u64 = null,
    digest: ?[]u8 = null,

    pub fn deinit(self: *OwnedDynamicFieldEntry, allocator: std.mem.Allocator) void {
        if (self.name_type) |value| allocator.free(value);
        if (self.name_value_json) |value| allocator.free(value);
        if (self.bcs_name) |value| allocator.free(value);
        if (self.field_kind) |value| allocator.free(value);
        if (self.object_type) |value| allocator.free(value);
        if (self.object_id) |value| allocator.free(value);
        if (self.digest) |value| allocator.free(value);
    }

    pub fn clone(self: OwnedDynamicFieldEntry, allocator: std.mem.Allocator) !OwnedDynamicFieldEntry {
        return .{
            .name_type = if (self.name_type) |value| try allocator.dupe(u8, value) else null,
            .name_value_json = if (self.name_value_json) |value| try allocator.dupe(u8, value) else null,
            .bcs_name = if (self.bcs_name) |value| try allocator.dupe(u8, value) else null,
            .field_kind = if (self.field_kind) |value| try allocator.dupe(u8, value) else null,
            .object_type = if (self.object_type) |value| try allocator.dupe(u8, value) else null,
            .object_id = if (self.object_id) |value| try allocator.dupe(u8, value) else null,
            .version = self.version,
            .digest = if (self.digest) |value| try allocator.dupe(u8, value) else null,
        };
    }
};

pub const OwnedDynamicFieldPage = struct {
    entries: []OwnedDynamicFieldEntry,
    next_cursor: ?[]u8 = null,
    has_next_page: bool = false,

    pub fn deinit(self: *OwnedDynamicFieldPage, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
        if (self.next_cursor) |value| allocator.free(value);
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

pub fn extractDynamicFieldPage(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedDynamicFieldPage {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const data = result.object.get("data") orelse return error.InvalidResponse;
    if (data != .array) return error.InvalidResponse;

    const entries = try allocator.alloc(OwnedDynamicFieldEntry, data.array.items.len);
    errdefer allocator.free(entries);

    for (data.array.items, 0..) |item, index| {
        if (item != .object) return error.InvalidResponse;

        var name_type: ?[]u8 = null;
        var name_value_json: ?[]u8 = null;
        if (item.object.get("name")) |name_value| {
            if (name_value == .object) {
                name_type = try dupeOptionalStringField(allocator, name_value.object, "type");
                if (name_value.object.get("value")) |raw_name_value| {
                    name_value_json = try stringifyJsonValue(allocator, raw_name_value);
                }
            }
        }

        entries[index] = .{
            .name_type = name_type,
            .name_value_json = name_value_json,
            .bcs_name = try dupeOptionalStringField(allocator, item.object, "bcsName"),
            .field_kind = try dupeOptionalStringField(allocator, item.object, "type"),
            .object_type = try dupeOptionalStringField(allocator, item.object, "objectType"),
            .object_id = try dupeOptionalStringField(allocator, item.object, "objectId"),
            .version = parseOptionalU64(item.object.get("version")),
            .digest = try dupeOptionalStringField(allocator, item.object, "digest"),
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

test "extractDynamicFieldPage parses D3-style pagination envelopes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var page = try extractDynamicFieldPage(allocator,
        \\{"result":{"data":[{"name":{"type":"address","value":"0xowner"},"bcsName":"AQ==","type":"DynamicField","objectType":"0x2::example::Field","objectId":"0xchild","version":"4","digest":"digest-1"}],"nextCursor":"cursor-2","hasNextPage":true}}
    );
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.entries.len);
    try testing.expectEqualStrings("address", page.entries[0].name_type.?);
    try testing.expectEqualStrings("\"0xowner\"", page.entries[0].name_value_json.?);
    try testing.expectEqualStrings("0xchild", page.entries[0].object_id.?);
    try testing.expectEqual(@as(?u64, 4), page.entries[0].version);
    try testing.expectEqualStrings("cursor-2", page.next_cursor.?);
    try testing.expect(page.has_next_page);
}
