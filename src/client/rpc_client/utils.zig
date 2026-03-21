/// client/rpc_client/utils.zig - Utility functions for RPC client
const std = @import("std");

/// Duplicate optional string
pub fn dupeOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    const slice = value orelse return null;
    return try allocator.dupe(u8, slice);
}

/// Duplicate string list
pub fn dupeStringList(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    if (values.len == 0) return &.{};

    const duped = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(duped);

    for (values, 0..) |value, index| {
        duped[index] = try allocator.dupe(u8, value);
        errdefer {
            var i: usize = 0;
            while (i < index) : (i += 1) allocator.free(duped[i]);
        }
    }

    return duped;
}

/// Free string list
pub fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

/// Parse JSON result exists
pub fn parseJsonResultExists(allocator: std.mem.Allocator, response: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return false;
    const result = parsed.value.object.get("result") orelse return false;

    return switch (result) {
        .null => false,
        else => true,
    };
}

/// Extract execute digest from response
pub fn extractExecuteDigest(allocator: std.mem.Allocator, response: []const u8) !?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const result = parsed.value.object.get("result") orelse return null;
    if (result != .object) return null;
    const digest = result.object.get("digest") orelse return null;
    if (digest != .string) return null;
    return try allocator.dupe(u8, digest.string);
}

/// Extract HTTP error message
pub fn extractHttpErrorMessage(allocator: std.mem.Allocator, response_body: []const u8) !?[]const u8 {
    const trimmed = std.mem.trim(u8, response_body, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch {
        return try allocator.dupe(u8, trimmed);
    };
    defer parsed.deinit();

    if (parsed.value.object.get("message")) |message| {
        if (message == .string) {
            return try allocator.dupe(u8, message.string);
        }
    }

    return try allocator.dupe(u8, trimmed);
}

/// Check if value is valid hex string
pub fn isValidHex(value: []const u8) bool {
    if (value.len == 0) return false;
    
    const start: usize = if (std.mem.startsWith(u8, value, "0x")) 2 else 0;
    if (start == value.len) return false;

    for (value[start..]) |c| {
        if (!isHexDigit(c)) return false;
    }
    return true;
}

/// Check if character is hex digit
fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or
           (c >= 'a' and c <= 'f') or
           (c >= 'A' and c <= 'F');
}

/// Check if value is valid Sui address
pub fn isValidAddress(value: []const u8) bool {
    if (!std.mem.startsWith(u8, value, "0x")) return false;
    const hex_part = value[2..];
    return hex_part.len == 64 and isValidHex(value);
}

/// Check if value is valid object ID
pub fn isValidObjectId(value: []const u8) bool {
    return isValidAddress(value);
}

/// Truncate string with ellipsis
pub fn truncateString(allocator: std.mem.Allocator, value: []const u8, max_len: usize) ![]const u8 {
    if (value.len <= max_len) {
        return allocator.dupe(u8, value);
    }

    const truncated_len = max_len - 3;
    var result = try allocator.alloc(u8, max_len);
    @memcpy(result[0..truncated_len], value[0..truncated_len]);
    @memcpy(result[truncated_len..], "...");
    return result;
}

/// Format JSON value for display
pub fn formatJsonValue(writer: anytype, value: std.json.Value, indent: usize) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.print("{}", .{b}),
        .integer => |i| try writer.print("{}", .{i}),
        .float => |f| try writer.print("{}", .{f}),
        .string => |s| try writer.print("\"{s}\"", .{s}),
        .array => |arr| {
            try writer.writeAll("[\n");
            for (arr.items, 0..) |item, i| {
                try writer.writeByteNTimes(' ', indent + 2);
                try formatJsonValue(writer, item, indent + 2);
                if (i < arr.items.len - 1) try writer.writeAll(",");
                try writer.writeAll("\n");
            }
            try writer.writeByteNTimes(' ', indent);
            try writer.writeAll("]");
        },
        .object => |obj| {
            try writer.writeAll("{\n");
            var it = obj.iterator();
            var i: usize = 0;
            const count = obj.count();
            while (it.next()) |entry| : (i += 1) {
                try writer.writeByteNTimes(' ', indent + 2);
                try writer.print("\"{s}\": ", .{entry.key_ptr.*});
                try formatJsonValue(writer, entry.value_ptr.*, indent + 2);
                if (i < count - 1) try writer.writeAll(",");
                try writer.writeAll("\n");
            }
            try writer.writeByteNTimes(' ', indent);
            try writer.writeAll("}");
        },
        .number_string => |s| try writer.print("{s}", .{s}),
    }
}

// ============================================================
// Tests
// ============================================================

test "dupeOptionalString with value" {
    const testing = std.testing;

    const result = try dupeOptionalString(testing.allocator, "test");
    defer if (result) |r| testing.allocator.free(r);

    try testing.expectEqualStrings("test", result.?);
}

test "dupeOptionalString without value" {
    const testing = std.testing;

    const result = try dupeOptionalString(testing.allocator, null);
    try testing.expect(result == null);
}

test "dupeStringList" {
    const testing = std.testing;

    const values = &[_][]const u8{ "a", "b", "c" };
    const result = try dupeStringList(testing.allocator, values);
    defer freeStringList(testing.allocator, result);

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqualStrings("a", result[0]);
    try testing.expectEqualStrings("b", result[1]);
    try testing.expectEqualStrings("c", result[2]);
}

test "parseJsonResultExists" {
    const testing = std.testing;

    try testing.expect(try parseJsonResultExists(testing.allocator, "{\"result\":\"data\"}"));
    try testing.expect(!(try parseJsonResultExists(testing.allocator, "{\"result\":null}")));
    try testing.expect(!(try parseJsonResultExists(testing.allocator, "{}")));
}

test "extractExecuteDigest" {
    const testing = std.testing;

    const json = "{\"result\":{\"digest\":\"abc123\"}}";
    const digest = try extractExecuteDigest(testing.allocator, json);
    defer if (digest) |d| testing.allocator.free(d);

    try testing.expectEqualStrings("abc123", digest.?);
}

test "isValidHex" {
    const testing = std.testing;

    try testing.expect(isValidHex("0x1234"));
    try testing.expect(isValidHex("1234"));
    try testing.expect(!isValidHex("0x123g"));
    try testing.expect(!isValidHex(""));
    try testing.expect(!isValidHex("0x"));
}

test "isValidAddress" {
    const testing = std.testing;

    try testing.expect(isValidAddress("0x" ++ "1" ** 64));
    try testing.expect(!isValidAddress("0x1234"));
    try testing.expect(!isValidAddress("not_an_address"));
}

test "truncateString" {
    const testing = std.testing;

    const result = try truncateString(testing.allocator, "hello world", 8);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("hello...", result);
}

test "truncateString short" {
    const testing = std.testing;

    const result = try truncateString(testing.allocator, "hi", 8);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("hi", result);
}
