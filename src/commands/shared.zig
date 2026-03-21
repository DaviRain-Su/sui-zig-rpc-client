/// commands/shared.zig - 命令模块共享工具函数
const std = @import("std");
const cli = @import("../cli.zig");
const client = @import("../root.zig");

/// 打印响应，支持美化输出
pub fn printResponse(allocator: std.mem.Allocator, writer: anytype, response: []const u8, pretty: bool) !void {
    if (!pretty) {
        try writer.print("{s}\n", .{response});
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    try writer.print("{f}\n", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
}

/// 打印结构化的 JSON 值
pub fn printStructuredJson(writer: anytype, value: anytype, pretty: bool) !void {
    if (pretty) {
        try writer.print("{f}\n", .{std.json.fmt(value, .{ .whitespace = .indent_2 })});
        return;
    }

    try writer.print("{f}\n", .{std.json.fmt(value, .{})});
}

/// 从 JSON 对象中获取任意指定名称的字段
pub fn jsonObjectFieldAny(object: std.json.ObjectMap, comptime names: []const []const u8) ?std.json.Value {
    inline for (names) |name| {
        if (object.get(name)) |value| return value;
    }
    return null;
}

/// 解析可选的 JSON 字符串字段
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

/// 解析可选的 JSON 布尔字段
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

/// 解析可选的 JSON U64 字段
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

/// 解析必需的 JSON 字符串
pub fn parseRequiredJsonString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) ![]u8 {
    return try parseOptionalJsonString(allocator, object, names) orelse error.InvalidCli;
}

/// 解析可选的 JSON 字符串数组
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

/// 检查文本是否包含未解析的 Move 函数占位符
pub fn stringContainsUnresolvedMoveFunctionPlaceholder(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "<arg") != null or
        std.mem.indexOf(u8, text, "0x<") != null or
        std.mem.eql(u8, text, "<alias-or-address>");
}

/// 递归检查 JSON 值是否包含未解析的占位符
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

/// 渲染 JSON 值为紧凑字符串
pub fn renderJsonValueCompact(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var rendered = std.ArrayList(u8){};
    defer rendered.deinit(allocator);
    try rendered.writer(allocator).print("{f}", .{std.json.fmt(value, .{})});
    return try rendered.toOwnedSlice(allocator);
}

/// Shell 转义并打印参数列表
pub fn printShellEscapedArgv(writer: anytype, argv: []const []const u8) !void {
    for (argv, 0..) |arg, i| {
        if (i > 0) try writer.writeAll(" ");
        const needs_quote = std.mem.indexOfAny(u8, arg, " \\'\"$|&;<>(){}[]*?#") != null;
        if (needs_quote) {
            try writer.writeAll("'");
            // 转义单引号: ' -> '\''
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

/// 检查请求工件 JSON 是否可执行（无占位符）
pub fn requestArtifactJsonIsExecutable(allocator: std.mem.Allocator, request_json: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, request_json, .{});
    defer parsed.deinit();
    return !jsonValueContainsUnresolvedMoveFunctionPlaceholder(parsed.value);
}

/// 替换拥有的可选值
pub fn replaceOwnedOptionalValue(
    allocator: std.mem.Allocator,
    owned_slot: *?[]const u8,
    value_slot: *?[]const u8,
    value: []u8,
) void {
    if (owned_slot.*) |old| allocator.free(old);
    owned_slot.* = value;
    value_slot.* = value;
}

/// 追加拥有的重复值到数组
pub fn appendOwnedRepeatedValue(
    allocator: std.mem.Allocator,
    items: *std.ArrayListUnmanaged([]const u8),
    owned_items: *std.ArrayListUnmanaged([]const u8),
    value: []const u8,
) !void {
    const owned = try allocator.dupe(u8, value);
    try items.append(allocator, owned);
    try owned_items.append(allocator, owned);
}

/// 交易构建错误类型
pub const TxBuildError = error{
    InvalidCli,
    InvalidConfig,
    NetworkError,
    RpcError,
    Timeout,
    OutOfMemory,
} || std.mem.Allocator.Error;

/// 命令结果类型
pub const CommandResult = union(enum) {
    success: []const u8,
    challenge_required: []const u8,
    err: TxBuildError,

    pub fn deinit(self: *CommandResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |value| allocator.free(value),
            .challenge_required => |value| allocator.free(value),
            .err => {},
        }
    }
};

// ============================================================
// 测试
// ============================================================

test "printResponse outputs raw response when pretty=false" {
    const testing = std.testing;
    var output = std.ArrayList(u8){};
    defer output.deinit(testing.allocator);

    const response = "{\"result\":\"ok\"}";
    try printResponse(testing.allocator, output.writer(), response, false);

    try testing.expectEqualStrings("{\"result\":\"ok\"}\n", output.items);
}

test "printResponse formats JSON when pretty=true" {
    const testing = std.testing;
    var output = std.ArrayList(u8){};
    defer output.deinit(testing.allocator);

    const response = "{\"result\":\"ok\"}";
    try printResponse(testing.allocator, output.writer(), response, true);

    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "{\n"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "result"));
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

test "printShellEscapedArgv handles simple args" {
    const testing = std.testing;
    var output = std.ArrayList(u8){};
    defer output.deinit(testing.allocator);

    const argv = &.{ "cmd", "--arg", "value" };
    try printShellEscapedArgv(output.writer(), argv);

    try testing.expectEqualStrings("cmd --arg value\n", output.items);
}

test "printShellEscapedArgv escapes special chars" {
    const testing = std.testing;
    var output = std.ArrayList(u8){};
    defer output.deinit(testing.allocator);

    const argv = &.{"arg with space"};
    try printShellEscapedArgv(output.writer(), argv);

    try testing.expect(std.mem.startsWith(u8, output.items, "'"));
    try testing.expect(std.mem.endsWith(u8, output.items, "'\n"));
}

test "parseOptionalJsonU64 handles integer" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"count\":42}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const value = try parseOptionalJsonU64(parsed.value.object, &.{"count"});
    try testing.expectEqual(@as(u64, 42), value.?);
}

test "parseOptionalJsonU64 handles string number" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"count\":\"100\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const value = try parseOptionalJsonU64(parsed.value.object, &.{"count"});
    try testing.expectEqual(@as(u64, 100), value.?);
}
