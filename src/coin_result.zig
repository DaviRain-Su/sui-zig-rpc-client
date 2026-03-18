const std = @import("std");

pub const OwnedCoinEntry = struct {
    coin_type: ?[]u8 = null,
    coin_object_id: ?[]u8 = null,
    version: ?u64 = null,
    digest: ?[]u8 = null,
    balance: ?[]u8 = null,
    previous_transaction: ?[]u8 = null,

    pub fn deinit(self: *OwnedCoinEntry, allocator: std.mem.Allocator) void {
        if (self.coin_type) |value| allocator.free(value);
        if (self.coin_object_id) |value| allocator.free(value);
        if (self.digest) |value| allocator.free(value);
        if (self.balance) |value| allocator.free(value);
        if (self.previous_transaction) |value| allocator.free(value);
    }

    pub fn clone(self: OwnedCoinEntry, allocator: std.mem.Allocator) !OwnedCoinEntry {
        return .{
            .coin_type = if (self.coin_type) |value| try allocator.dupe(u8, value) else null,
            .coin_object_id = if (self.coin_object_id) |value| try allocator.dupe(u8, value) else null,
            .version = self.version,
            .digest = if (self.digest) |value| try allocator.dupe(u8, value) else null,
            .balance = if (self.balance) |value| try allocator.dupe(u8, value) else null,
            .previous_transaction = if (self.previous_transaction) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn balanceU64(self: OwnedCoinEntry) ?u64 {
        const value = self.balance orelse return null;
        return std.fmt.parseInt(u64, value, 10) catch null;
    }
};

pub const OwnedCoinPage = struct {
    entries: []OwnedCoinEntry,
    next_cursor: ?[]u8 = null,
    has_next_page: bool = false,

    pub fn deinit(self: *OwnedCoinPage, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
        if (self.next_cursor) |value| allocator.free(value);
    }

    pub fn selectLargestCoinIndex(self: *const OwnedCoinPage) ?usize {
        var best_index: ?usize = null;
        var best_balance: u64 = 0;

        for (self.entries, 0..) |entry, index| {
            if (entry.coin_object_id == null) continue;
            const balance = entry.balanceU64() orelse continue;
            if (best_index == null or balance > best_balance) {
                best_index = index;
                best_balance = balance;
            }
        }

        return best_index;
    }

    pub fn selectSmallestSufficientCoinIndex(
        self: *const OwnedCoinPage,
        min_balance: u64,
    ) ?usize {
        var best_index: ?usize = null;
        var best_balance: u64 = std.math.maxInt(u64);

        for (self.entries, 0..) |entry, index| {
            if (entry.coin_object_id == null) continue;
            const balance = entry.balanceU64() orelse continue;
            if (balance < min_balance) continue;
            if (best_index == null or balance < best_balance) {
                best_index = index;
                best_balance = balance;
            }
        }

        return best_index;
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

pub fn extractCoinPage(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedCoinPage {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const data = result.object.get("data") orelse return error.InvalidResponse;
    if (data != .array) return error.InvalidResponse;

    const entries = try allocator.alloc(OwnedCoinEntry, data.array.items.len);
    errdefer allocator.free(entries);

    for (data.array.items, 0..) |item, index| {
        if (item != .object) return error.InvalidResponse;
        entries[index] = .{
            .coin_type = try dupeOptionalStringField(allocator, item.object, "coinType"),
            .coin_object_id = try dupeOptionalStringField(allocator, item.object, "coinObjectId"),
            .version = parseOptionalU64(item.object.get("version")),
            .digest = try dupeOptionalStringField(allocator, item.object, "digest"),
            .balance = try dupeOptionalStringField(allocator, item.object, "balance"),
            .previous_transaction = try dupeOptionalStringField(allocator, item.object, "previousTransaction"),
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

test "extractCoinPage parses coin pagination envelopes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var page = try extractCoinPage(allocator,
        \\{"result":{"data":[{"coinType":"0x2::sui::SUI","coinObjectId":"0xcoin1","version":"7","digest":"digest-1","balance":"42","previousTransaction":"0xprev-1"}],"nextCursor":"cursor-2","hasNextPage":true}}
    );
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.entries.len);
    try testing.expectEqualStrings("0x2::sui::SUI", page.entries[0].coin_type.?);
    try testing.expectEqualStrings("0xcoin1", page.entries[0].coin_object_id.?);
    try testing.expectEqual(@as(?u64, 7), page.entries[0].version);
    try testing.expectEqualStrings("digest-1", page.entries[0].digest.?);
    try testing.expectEqualStrings("42", page.entries[0].balance.?);
    try testing.expectEqualStrings("0xprev-1", page.entries[0].previous_transaction.?);
    try testing.expectEqualStrings("cursor-2", page.next_cursor.?);
    try testing.expect(page.has_next_page);
}

test "OwnedCoinPage selects largest and smallest sufficient coins" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var page = OwnedCoinPage{
        .entries = try allocator.alloc(OwnedCoinEntry, 3),
        .has_next_page = false,
    };
    defer page.deinit(allocator);

    page.entries[0] = .{
        .coin_object_id = try allocator.dupe(u8, "0xcoin-1"),
        .balance = try allocator.dupe(u8, "42"),
    };
    page.entries[1] = .{
        .coin_object_id = try allocator.dupe(u8, "0xcoin-2"),
        .balance = try allocator.dupe(u8, "7"),
    };
    page.entries[2] = .{
        .coin_object_id = try allocator.dupe(u8, "0xcoin-3"),
        .balance = try allocator.dupe(u8, "9"),
    };

    try testing.expectEqual(@as(?usize, 0), page.selectLargestCoinIndex());
    try testing.expectEqual(@as(?usize, 2), page.selectSmallestSufficientCoinIndex(8));
    try testing.expectEqual(@as(?usize, 1), page.selectSmallestSufficientCoinIndex(7));
    try testing.expectEqual(@as(?usize, null), page.selectSmallestSufficientCoinIndex(100));
}
