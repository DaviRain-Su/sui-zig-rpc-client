/// cli/utils.zig - Utility functions for CLI
const std = @import("std");

/// Set an optional string argument, taking ownership
pub fn setOptionalStringArg(
    allocator: std.mem.Allocator,
    value: []const u8,
    owned_ptr: *?[]const u8,
    ptr: *?[]const u8,
) !void {
    if (owned_ptr.*) |owned| {
        allocator.free(owned);
    }
    const duped = try allocator.dupe(u8, value);
    owned_ptr.* = duped;
    ptr.* = duped;
}

/// Set RPC URL with validation
pub fn setRpcUrl(
    allocator: std.mem.Allocator,
    rpc_url: *?[]const u8,
    owned_rpc_url: *?[]const u8,
    url: []const u8,
) !void {
    // Basic URL validation
    if (!isValidUrl(url)) {
        return error.InvalidCli;
    }
    try setOptionalStringArg(allocator, url, owned_rpc_url, rpc_url);
}

/// Check if URL is valid
fn isValidUrl(url: []const u8) bool {
    // Must start with http:// or https://
    return std.mem.startsWith(u8, url, "http://") or
           std.mem.startsWith(u8, url, "https://");
}

/// Parse boolean value from string
pub fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "1") or
        std.mem.eql(u8, value, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "0") or
        std.mem.eql(u8, value, "no")) {
        return false;
    }
    return error.InvalidCli;
}

/// Parse comma-separated list
pub fn parseCommaSeparatedList(allocator: std.mem.Allocator, value: []const u8) ![]const []const u8 {
    if (value.len == 0) return &[]const []const u8{};

    var list = std.ArrayList([]const u8).init(allocator);
    errdefer list.deinit();

    var it = std.mem.split(u8, value, ",");
    while (it.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t");
        if (trimmed.len > 0) {
            try list.append(try allocator.dupe(u8, trimmed));
        }
    }

    return list.toOwnedSlice();
}

/// Free comma-separated list
pub fn freeCommaSeparatedList(allocator: std.mem.Allocator, list: []const []const u8) void {
    for (list) |item| {
        allocator.free(item);
    }
    allocator.free(list);
}

/// Format duration in human-readable format
pub fn formatDuration(ms: u64) []const u8 {
    if (ms < 1000) {
        return "<1s";
    } else if (ms < 60_000) {
        return "<1m";
    } else if (ms < 3_600_000) {
        return "<1h";
    } else {
        return ">1h";
    }
}

/// Truncate string with ellipsis
pub fn truncateString(allocator: std.mem.Allocator, value: []const u8, max_len: usize) ![]const u8 {
    if (value.len <= max_len) {
        return allocator.dupe(u8, value);
    }

    const truncated_len = max_len - 3; // Account for "..."
    var result = try allocator.alloc(u8, max_len);
    @memcpy(result[0..truncated_len], value[0..truncated_len]);
    @memcpy(result[truncated_len..], "...");
    return result;
}

/// Convert MIST to SUI string
pub fn mistToSui(mist: u64) []const u8 {
    const sui = @as(f64, @floatFromInt(mist)) / 1_000_000_000.0;
    var buf: [64]u8 = undefined;
    return std.fmt.bufPrint(&buf, "{d:.9}", .{sui}) catch "0.000000000";
}

/// Format balance with unit
pub fn formatBalance(allocator: std.mem.Allocator, mist: u64) ![]const u8 {
    const sui_str = mistToSui(mist);
    return std.fmt.allocPrint(allocator, "{s} SUI ({d} MIST)", .{ sui_str, mist });
}

/// Read file contents
pub fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 10 * 1024 * 1024) { // 10MB limit
        return error.FileTooLarge;
    }

    return try file.readToEndAlloc(allocator, @intCast(stat.size));
}

/// Write file contents
pub fn writeFileContents(path: []const u8, contents: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try file.writeAll(contents);
}

/// Get home directory
pub fn getHomeDir() ?[]const u8 {
    return std.posix.getenv("HOME") orelse
           std.posix.getenv("USERPROFILE");
}

/// Expand tilde in path
pub fn expandTilde(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, path, "~/")) {
        return allocator.dupe(u8, path);
    }

    const home = getHomeDir() orelse return allocator.dupe(u8, path);
    return std.fs.path.join(allocator, &.{ home, path[2..] });
}

/// Check if running in terminal
pub fn isTerminal() bool {
    return std.io.getStdOut().isTty();
}

/// Get terminal width
pub fn getTerminalWidth() u16 {
    if (!isTerminal()) return 80;
    // Default to 80 if can't determine
    return 80;
}

/// Wrap text to width
pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, width: usize) ![]const u8 {
    if (text.len <= width) {
        return allocator.dupe(u8, text);
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var line_start: usize = 0;
    while (line_start < text.len) {
        const line_end = @min(line_start + width, text.len);
        try result.appendSlice(text[line_start..line_end]);
        if (line_end < text.len) {
            try result.append('\n');
        }
        line_start = line_end;
    }

    return result.toOwnedSlice();
}

// ============================================================
// Tests
// ============================================================

test "setOptionalStringArg takes ownership" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var owned: ?[]const u8 = null;
    var ptr: ?[]const u8 = null;

    try setOptionalStringArg(allocator, "test", &owned, &ptr);
    try testing.expectEqualStrings("test", ptr.?);
    try testing.expectEqualStrings("test", owned.?);

    // Update with new value
    try setOptionalStringArg(allocator, "new", &owned, &ptr);
    try testing.expectEqualStrings("new", ptr.?);

    allocator.free(owned.?);
}

test "parseBool parses valid values" {
    const testing = std.testing;

    try testing.expect(try parseBool("true"));
    try testing.expect(try parseBool("1"));
    try testing.expect(try parseBool("yes"));

    try testing.expect(!(try parseBool("false")));
    try testing.expect(!(try parseBool("0")));
    try testing.expect(!(try parseBool("no")));
}

test "parseBool rejects invalid values" {
    const testing = std.testing;

    try testing.expectError(error.InvalidCli, parseBool("maybe"));
    try testing.expectError(error.InvalidCli, parseBool(""));
}

test "parseCommaSeparatedList" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const list = try parseCommaSeparatedList(allocator, "a,b,c");
    defer freeCommaSeparatedList(allocator, list);

    try testing.expectEqual(@as(usize, 3), list.len);
    try testing.expectEqualStrings("a", list[0]);
    try testing.expectEqualStrings("b", list[1]);
    try testing.expectEqualStrings("c", list[2]);
}

test "parseCommaSeparatedList handles whitespace" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const list = try parseCommaSeparatedList(allocator, " a , b , c ");
    defer freeCommaSeparatedList(allocator, list);

    try testing.expectEqual(@as(usize, 3), list.len);
    try testing.expectEqualStrings("a", list[0]);
}

test "truncateString" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const truncated = try truncateString(allocator, "hello world", 8);
    defer allocator.free(truncated);

    try testing.expectEqualStrings("hello...", truncated);
}

test "truncateString short string" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try truncateString(allocator, "hi", 8);
    defer allocator.free(result);

    try testing.expectEqualStrings("hi", result);
}

test "mistToSui" {
    const testing = std.testing;

    const result1 = mistToSui(1_000_000_000);
    try testing.expectEqualStrings("1.000000000", result1);

    const result2 = mistToSui(500_000_000);
    try testing.expectEqualStrings("0.500000000", result2);
}

test "formatBalance" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try formatBalance(allocator, 1_000_000_000);
    defer allocator.free(result);

    try testing.expect(std.mem.containsAtLeast(u8, result, 1, "1.000000000"));
    try testing.expect(std.mem.containsAtLeast(u8, result, 1, "SUI"));
    try testing.expect(std.mem.containsAtLeast(u8, result, 1, "1000000000"));
}

test "expandTilde" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const expanded = try expandTilde(allocator, "~/test");
    defer allocator.free(expanded);

    // Should either expand or return as-is if no home dir
    try testing.expect(std.mem.startsWith(u8, expanded, "/") or
                       std.mem.startsWith(u8, expanded, "~"));
}

test "wrapText" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const wrapped = try wrapText(allocator, "hello world test", 10);
    defer allocator.free(wrapped);

    try testing.expect(std.mem.indexOf(u8, wrapped, "\n") != null);
}
