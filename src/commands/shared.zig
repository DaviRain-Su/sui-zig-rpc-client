/// commands/shared.zig - Shared utility functions
const std = @import("std");
const types = @import("types.zig");

// Re-export types for convenience
pub const TxBuildError = types.TxBuildError;
pub const CommandResult = types.CommandResult;

/// Print response with optional pretty formatting
pub fn printResponse(allocator: std.mem.Allocator, writer: anytype, response: []const u8, pretty: bool) !void {
    if (!pretty) {
        try writer.print("{s}\n", .{response});
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    // Simple pretty print - just indent
    try writer.writeAll("{\n");
    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        try writer.print("  \"{s}\": {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    try writer.writeAll("}\n");
}

/// Print structured JSON value
pub fn printStructuredJson(writer: anytype, value: anytype, pretty: bool) !void {
    if (pretty) {
        try writer.print("{any}\n", .{value});
        return;
    }
    try writer.print("{any}\n", .{value});
}

/// Get JSON object field by alternative names
pub fn jsonObjectFieldAny(object: std.json.ObjectMap, comptime names: []const []const u8) ?std.json.Value {
    inline for (names) |name| {
        if (object.get(name)) |value| return value;
    }
    return null;
}

/// Parse optional JSON string
pub fn parseOptionalJsonString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]u8 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCli,
    };
}

/// Parse optional JSON bool
pub fn parseOptionalJsonBool(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?bool {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .bool => |flag| flag,
        else => error.InvalidCli,
    };
}

/// Parse optional JSON u64
pub fn parseOptionalJsonU64(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?u64 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .integer => |number| blk: {
            if (number < 0) return error.InvalidCli;
            break :blk @as(u64, @intCast(number));
        },
        .string => |text| try std.fmt.parseInt(u64, text, 10),
        else => error.InvalidCli,
    };
}

/// Parse required JSON string
pub fn parseRequiredJsonString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) ![]u8 {
    return try parseOptionalJsonString(allocator, object, names) orelse error.InvalidCli;
}

/// Parse optional JSON string array
pub fn parseOptionalJsonStringArray(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[][]u8 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .array => |arr| blk: {
            const result = try allocator.alloc([]u8, arr.items.len);
            errdefer allocator.free(result);
            for (arr.items, 0..) |item, i| {
                result[i] = switch (item) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => return error.InvalidCli,
                };
            }
            break :blk result;
        },
        else => error.InvalidCli,
    };
}

/// Check if text contains unresolved Move function placeholder
pub fn stringContainsUnresolvedMoveFunctionPlaceholder(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "<arg") != null or
        std.mem.indexOf(u8, text, "0x<") != null or
        std.mem.eql(u8, text, "<alias-or-address>");
}

/// Check if JSON value contains unresolved placeholder
pub fn jsonValueContainsUnresolvedMoveFunctionPlaceholder(value: std.json.Value) bool {
    return switch (value) {
        .string => |text| stringContainsUnresolvedMoveFunctionPlaceholder(text),
        .array => |arr| blk: {
            for (arr.items) |item| {
                if (jsonValueContainsUnresolvedMoveFunctionPlaceholder(item)) break :blk true;
            }
            break :blk false;
        },
        .object => |obj| blk: {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "preferredResolution")) continue;
                if (jsonValueContainsUnresolvedMoveFunctionPlaceholder(entry.value_ptr.*)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Check if request artifact JSON is executable
pub fn requestArtifactJsonIsExecutable(allocator: std.mem.Allocator, request_json: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, request_json, .{});
    defer parsed.deinit();
    return !jsonValueContainsUnresolvedMoveFunctionPlaceholder(parsed.value);
}

/// Shell escape and print argv
pub fn printShellEscapedArgv(writer: anytype, argv: []const []const u8) !void {
    for (argv, 0..) |arg, i| {
        if (i > 0) try writer.writeAll(" ");
        const needs_quote = std.mem.indexOfAny(u8, arg, " \\'\"$|&;<>(){}[]*?#") != null;
        if (needs_quote) {
            try writer.writeAll("'");
            var start: usize = 0;
            while (std.mem.indexOfScalar(u8, arg[start..], '\'')) |pos| {
                try writer.writeAll(arg[start .. start + pos]);
                try writer.writeAll("'\\''");
                start += pos + 1;
            }
            try writer.writeAll(arg[start..]);
            try writer.writeAll("'");
        } else {
            try writer.writeAll(arg);
        }
    }
    try writer.writeAll("\n");
}

// ============================================================
// Tests
// ============================================================

test "printResponse outputs raw response when pretty=false" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    const response = "{\"result\":\"ok\"}";
    try printResponse(testing.allocator, output.writer(), response, false);

    try testing.expectEqualStrings("{\"result\":\"ok\"}\n", output.items);
}

test "jsonObjectFieldAny finds field by alternative names" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"name\":\"test\",\"altName\":\"alt\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const value = jsonObjectFieldAny(parsed.value.object, &.{ "missing", "altName" });
    try testing.expect(value != null);
    try testing.expectEqualStrings("alt", value.?.string);
}

test "stringContainsUnresolvedMoveFunctionPlaceholder detects placeholders" {
    const testing = std.testing;

    try testing.expect(stringContainsUnresolvedMoveFunctionPlaceholder("<arg0>"));
    try testing.expect(stringContainsUnresolvedMoveFunctionPlaceholder("0x<package>"));
    try testing.expect(stringContainsUnresolvedMoveFunctionPlaceholder("<alias-or-address>"));
    try testing.expect(!stringContainsUnresolvedMoveFunctionPlaceholder("0x1234"));
}
