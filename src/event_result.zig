const std = @import("std");

pub const OwnedEventEntry = struct {
    tx_digest: ?[]u8 = null,
    event_seq: ?u64 = null,
    package_id: ?[]u8 = null,
    transaction_module: ?[]u8 = null,
    sender: ?[]u8 = null,
    type_name: ?[]u8 = null,
    parsed_json: ?[]u8 = null,
    bcs_encoding: ?[]u8 = null,
    bcs: ?[]u8 = null,
    timestamp_ms: ?u64 = null,

    pub fn deinit(self: *OwnedEventEntry, allocator: std.mem.Allocator) void {
        if (self.tx_digest) |value| allocator.free(value);
        if (self.package_id) |value| allocator.free(value);
        if (self.transaction_module) |value| allocator.free(value);
        if (self.sender) |value| allocator.free(value);
        if (self.type_name) |value| allocator.free(value);
        if (self.parsed_json) |value| allocator.free(value);
        if (self.bcs_encoding) |value| allocator.free(value);
        if (self.bcs) |value| allocator.free(value);
    }

    pub fn clone(self: OwnedEventEntry, allocator: std.mem.Allocator) !OwnedEventEntry {
        return .{
            .tx_digest = if (self.tx_digest) |value| try allocator.dupe(u8, value) else null,
            .event_seq = self.event_seq,
            .package_id = if (self.package_id) |value| try allocator.dupe(u8, value) else null,
            .transaction_module = if (self.transaction_module) |value| try allocator.dupe(u8, value) else null,
            .sender = if (self.sender) |value| try allocator.dupe(u8, value) else null,
            .type_name = if (self.type_name) |value| try allocator.dupe(u8, value) else null,
            .parsed_json = if (self.parsed_json) |value| try allocator.dupe(u8, value) else null,
            .bcs_encoding = if (self.bcs_encoding) |value| try allocator.dupe(u8, value) else null,
            .bcs = if (self.bcs) |value| try allocator.dupe(u8, value) else null,
            .timestamp_ms = self.timestamp_ms,
        };
    }
};

pub const OwnedEventPage = struct {
    entries: []OwnedEventEntry,
    next_cursor_tx_digest: ?[]u8 = null,
    next_cursor_event_seq: ?u64 = null,
    has_next_page: bool = false,

    pub fn deinit(self: *OwnedEventPage, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
        if (self.next_cursor_tx_digest) |value| allocator.free(value);
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

fn stringifyJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
}

fn extractCursor(
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
) !struct { tx_digest: ?[]u8, event_seq: ?u64 } {
    const cursor = value orelse return .{ .tx_digest = null, .event_seq = null };
    if (cursor != .object) return .{ .tx_digest = null, .event_seq = null };
    return .{
        .tx_digest = try dupeOptionalStringField(allocator, cursor.object, "txDigest"),
        .event_seq = parseOptionalU64(cursor.object.get("eventSeq")),
    };
}

pub fn extractEventPage(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedEventPage {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const data = result.object.get("data") orelse return error.InvalidResponse;
    if (data != .array) return error.InvalidResponse;

    const entries = try allocator.alloc(OwnedEventEntry, data.array.items.len);
    errdefer allocator.free(entries);

    for (data.array.items, 0..) |item, index| {
        if (item != .object) return error.InvalidResponse;
        const id = try extractCursor(allocator, item.object.get("id"));
        errdefer if (id.tx_digest) |value| allocator.free(value);
        entries[index] = .{
            .tx_digest = id.tx_digest,
            .event_seq = id.event_seq,
            .package_id = try dupeOptionalStringField(allocator, item.object, "packageId"),
            .transaction_module = try dupeOptionalStringField(allocator, item.object, "transactionModule"),
            .sender = try dupeOptionalStringField(allocator, item.object, "sender"),
            .type_name = try dupeOptionalStringField(allocator, item.object, "type"),
            .parsed_json = if (item.object.get("parsedJson")) |value| try stringifyJsonValue(allocator, value) else null,
            .bcs_encoding = try dupeOptionalStringField(allocator, item.object, "bcsEncoding"),
            .bcs = try dupeOptionalStringField(allocator, item.object, "bcs"),
            .timestamp_ms = parseOptionalU64(item.object.get("timestampMs")),
        };
    }

    const next_cursor = try extractCursor(allocator, result.object.get("nextCursor"));
    return .{
        .entries = entries,
        .next_cursor_tx_digest = next_cursor.tx_digest,
        .next_cursor_event_seq = next_cursor.event_seq,
        .has_next_page = if (result.object.get("hasNextPage")) |value|
            switch (value) {
                .bool => |flag| flag,
                else => false,
            }
        else
            false,
    };
}

test "extractEventPage parses event pagination envelopes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var page = try extractEventPage(allocator,
        \\{"result":{"data":[{"id":{"txDigest":"0xdigest","eventSeq":"7"},"packageId":"0x2","transactionModule":"coin","sender":"0xsender","type":"0x2::event::Thing","parsedJson":{"amount":"9"},"bcsEncoding":"base64","bcs":"AQ==","timestampMs":"42"}],"nextCursor":{"txDigest":"0xnext","eventSeq":"8"},"hasNextPage":true}}
    );
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.entries.len);
    try testing.expectEqualStrings("0xdigest", page.entries[0].tx_digest.?);
    try testing.expectEqual(@as(?u64, 7), page.entries[0].event_seq);
    try testing.expectEqualStrings("0x2", page.entries[0].package_id.?);
    try testing.expectEqualStrings("coin", page.entries[0].transaction_module.?);
    try testing.expectEqualStrings("0xsender", page.entries[0].sender.?);
    try testing.expectEqualStrings("0x2::event::Thing", page.entries[0].type_name.?);
    try testing.expectEqualStrings("{\"amount\":\"9\"}", page.entries[0].parsed_json.?);
    try testing.expectEqualStrings("base64", page.entries[0].bcs_encoding.?);
    try testing.expectEqualStrings("AQ==", page.entries[0].bcs.?);
    try testing.expectEqual(@as(?u64, 42), page.entries[0].timestamp_ms);
    try testing.expectEqualStrings("0xnext", page.next_cursor_tx_digest.?);
    try testing.expectEqual(@as(?u64, 8), page.next_cursor_event_seq);
    try testing.expect(page.has_next_page);
}
