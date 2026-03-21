/// client/rpc_client/error.zig - Error types for RPC client
const std = @import("std");

/// Client error types
pub const ClientError = error{
    Timeout,
    HttpError,
    RpcError,
    InvalidResponse,
    ConnectionFailed,
    RequestFailed,
    ParseError,
};

/// RPC error detail
pub const RpcErrorDetail = struct {
    code: ?i64 = null,
    message: []const u8,

    pub fn format(
        self: RpcErrorDetail,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.code) |code| {
            try writer.print("RPC Error (code={}): {s}", .{ code, self.message });
        } else {
            try writer.print("RPC Error: {s}", .{self.message});
        }
    }
};

/// Transport statistics
pub const TransportStats = struct {
    request_count: usize = 0,
    elapsed_time_ms: u64 = 0,
    rate_limited_time_ms: u64 = 0,

    pub fn recordRequest(self: *TransportStats, elapsed_ms: u64) void {
        self.request_count += 1;
        self.elapsed_time_ms += elapsed_ms;
    }

    pub fn recordRateLimit(self: *TransportStats, wait_ms: u64) void {
        self.rate_limited_time_ms += wait_ms;
    }

    pub fn averageResponseTime(self: TransportStats) u64 {
        if (self.request_count == 0) return 0;
        return self.elapsed_time_ms / self.request_count;
    }
};

/// Result with error detail
pub fn ResultWithError(comptime T: type) type {
    return union(enum) {
        success: T,
        error_detail: RpcErrorDetail,

        pub fn isSuccess(self: @This()) bool {
            return self == .success;
        }

        pub fn getErrorMessage(self: @This()) ?[]const u8 {
            return switch (self) {
                .error_detail => |e| e.message,
                else => null,
            };
        }
    };
}

/// Parse error from JSON response
pub fn parseErrorFromJson(allocator: std.mem.Allocator, response: []const u8) ?RpcErrorDetail {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch return null;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return null;

    const error_value = root.object.get("error") orelse return null;
    if (error_value != .object) return null;

    var code: ?i64 = null;
    if (error_value.object.get("code")) |code_value| {
        if (code_value == .integer) {
            code = code_value.integer;
        }
    }

    var message: []const u8 = "unknown error";
    if (error_value.object.get("message")) |message_value| {
        if (message_value == .string) {
            message = message_value.string;
        }
    }

    return .{
        .code = code,
        .message = allocator.dupe(u8, message) catch message,
    };
}

// ============================================================
// Tests
// ============================================================

test "RpcErrorDetail formatting with code" {
    const testing = std.testing;

    const error_detail = RpcErrorDetail{
        .code = -32000,
        .message = "Server error",
    };

    var buf: [256]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{}", .{error_detail});
    try testing.expect(std.mem.containsAtLeast(u8, result, 1, "-32000"));
    try testing.expect(std.mem.containsAtLeast(u8, result, 1, "Server error"));
}

test "RpcErrorDetail formatting without code" {
    const testing = std.testing;

    const error_detail = RpcErrorDetail{
        .message = "Network error",
    };

    var buf: [256]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{}", .{error_detail});
    try testing.expect(std.mem.containsAtLeast(u8, result, 1, "Network error"));
}

test "TransportStats recordRequest" {
    const testing = std.testing;

    var stats = TransportStats{};
    stats.recordRequest(100);
    stats.recordRequest(200);

    try testing.expectEqual(@as(usize, 2), stats.request_count);
    try testing.expectEqual(@as(u64, 300), stats.elapsed_time_ms);
    try testing.expectEqual(@as(u64, 150), stats.averageResponseTime());
}

test "TransportStats recordRateLimit" {
    const testing = std.testing;

    var stats = TransportStats{};
    stats.recordRateLimit(1000);

    try testing.expectEqual(@as(u64, 1000), stats.rate_limited_time_ms);
}

test "ResultWithError success" {
    const testing = std.testing;

    const result: ResultWithError(u64) = .{ .success = 42 };
    try testing.expect(result.isSuccess());
    try testing.expectEqual(@as(?[]const u8, null), result.getErrorMessage());
}

test "ResultWithError error" {
    const testing = std.testing;

    const result: ResultWithError(u64) = .{
        .error_detail = .{ .message = "test error" },
    };
    try testing.expect(!result.isSuccess());
    try testing.expectEqualStrings("test error", result.getErrorMessage().?);
}

test "parseErrorFromJson with code" {
    const testing = std.testing;

    const json = "{\"error\":{\"code\":-32000,\"message\":\"Server error\"}}";
    const error_detail = parseErrorFromJson(testing.allocator, json);
    defer if (error_detail) |e| testing.allocator.free(e.message);

    try testing.expect(error_detail != null);
    try testing.expectEqual(@as(i64, -32000), error_detail.?.code.?);
    try testing.expectEqualStrings("Server error", error_detail.?.message);
}

test "parseErrorFromJson without code" {
    const testing = std.testing;

    const json = "{\"error\":{\"message\":\"Parse error\"}}";
    const error_detail = parseErrorFromJson(testing.allocator, json);
    defer if (error_detail) |e| testing.allocator.free(e.message);

    try testing.expect(error_detail != null);
    try testing.expect(error_detail.?.code == null);
    try testing.expectEqualStrings("Parse error", error_detail.?.message);
}

test "parseErrorFromJson no error" {
    const testing = std.testing;

    const json = "{\"result\":\"success\"}";
    const error_detail = parseErrorFromJson(testing.allocator, json);

    try testing.expect(error_detail == null);
}
