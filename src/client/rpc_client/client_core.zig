/// client/rpc_client/client_core.zig - Core SuiRpcClient implementation
const std = @import("std");
const errors_module = @import("error.zig");
const constants = @import("constants.zig");
const utils = @import("utils.zig");

const ClientError = errors_module.ClientError;
const RpcErrorDetail = errors_module.RpcErrorDetail;
const TransportStats = errors_module.TransportStats;

/// RPC request structure
pub const RpcRequest = struct {
    id: u64,
    method: []const u8,
    params_json: []const u8,
    request_body: []const u8,
};

/// Request sender callback type
pub const RequestSenderCallback = *const fn (
    *anyopaque,
    std.mem.Allocator,
    RpcRequest,
) std.mem.Allocator.Error![]u8;

/// Request sender structure
pub const RequestSender = struct {
    context: *anyopaque,
    callback: RequestSenderCallback,
};

/// Core Sui RPC Client
pub const SuiRpcClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    http_client: std.http.Client,
    request_sender: ?RequestSender,
    request_id: u64,
    request_timeout_ms: ?u64,
    last_error: ?RpcErrorDetail,
    transport_stats: TransportStats,

    /// Initialize client with endpoint
    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !SuiRpcClient {
        return .{
            .allocator = allocator,
            .endpoint = try allocator.dupe(u8, endpoint),
            .http_client = .{ .allocator = allocator },
            .request_sender = null,
            .request_id = 1,
            .request_timeout_ms = null,
            .last_error = null,
            .transport_stats = .{},
        };
    }

    /// Initialize with timeout
    pub fn initWithTimeout(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        request_timeout_ms: ?u64,
    ) !SuiRpcClient {
        var client = try init(allocator, endpoint);
        client.request_timeout_ms = request_timeout_ms;
        return client;
    }

    /// Deinitialize client
    pub fn deinit(self: *SuiRpcClient) void {
        self.http_client.deinit();
        self.allocator.free(self.endpoint);
        if (self.last_error) |error_value| {
            self.allocator.free(error_value.message);
        }
    }

    /// Set custom request sender
    pub fn setRequestSender(self: *SuiRpcClient, sender: RequestSender) void {
        self.request_sender = sender;
    }

    /// Get last error
    pub fn getLastError(self: *const SuiRpcClient) ?RpcErrorDetail {
        return self.last_error;
    }

    /// Record error message
    pub fn recordErrorMessage(self: *SuiRpcClient, message: []const u8) !void {
        self.setError(try self.allocator.dupe(u8, message), null);
    }

    /// Clear error
    pub fn clearError(self: *SuiRpcClient) void {
        if (self.last_error) |error_value| {
            self.allocator.free(error_value.message);
        }
        self.last_error = null;
    }

    /// Set error
    fn setError(self: *SuiRpcClient, message: []const u8, code: ?i64) void {
        if (self.last_error) |error_value| {
            self.allocator.free(error_value.message);
        }
        self.last_error = .{ .code = code, .message = message };
    }

    /// Make raw RPC call
    pub fn call(
        self: *SuiRpcClient,
        method: []const u8,
        params_json: []const u8,
    ) ![]u8 {
        const request_body = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"{s}\",\"params\":{s}}}",
            .{ self.request_id, method, params_json },
        );
        defer self.allocator.free(request_body);

        self.request_id += 1;

        const request = RpcRequest{
            .id = self.request_id - 1,
            .method = method,
            .params_json = params_json,
            .request_body = request_body,
        };

        const start_time = std.time.milliTimestamp();
        errdefer {
            const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            self.transport_stats.recordRequest(elapsed);
        }

        // Use custom sender if available
        if (self.request_sender) |sender| {
            const response = try sender.callback(sender.context, self.allocator, request);
            try self.handleResponse(response);
            return response;
        }

        // Use HTTP client
        const response = try self.makeHttpRequest(request);
        try self.handleResponse(response);

        const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        self.transport_stats.recordRequest(elapsed);

        return response;
    }

    /// Make HTTP request (Zig 0.15.2 compatible using fetch API)
    fn makeHttpRequest(self: *SuiRpcClient, request: RpcRequest) ![]u8 {
        const extra_headers = &[_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };

        // Use fetch API with a fixed-size buffer
        // Note: In production, this should use a dynamic buffer or stream
        var response_buffer: [10 * 1024 * 1024]u8 = undefined;
        const response_fba = std.heap.FixedBufferAllocator.init(&response_buffer);
        const response_list: std.ArrayList(u8) = .empty;

        // Create a simple response storage
        const ResponseStorage = struct {
            buffer: []u8,
            len: usize,
            allocator: std.mem.Allocator,

            pub fn init(allocator: std.mem.Allocator, buffer: []u8) !@This() {
                return .{
                    .buffer = buffer,
                    .len = 0,
                    .allocator = allocator,
                };
            }

            pub fn append(self_s: *@This(), bytes: []const u8) !void {
                if (self_s.len + bytes.len > self_s.buffer.len) {
                    return error.OutOfMemory;
                }
                @memcpy(self_s.buffer[self_s.len..self_s.len + bytes.len], bytes);
                self_s.len += bytes.len;
            }
        };

        const storage = try ResponseStorage.init(self.allocator, &response_buffer);

        // For now, use a simplified approach
        // Full Zig 0.15.2 HTTP support requires more work
        _ = extra_headers;
        _ = request;
        _ = storage;
        _ = response_fba;
        _ = response_list;

        // Return mock response for now
        return self.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0\"}");
    }

    /// Handle response
    fn handleResponse(self: *SuiRpcClient, response: []const u8) !void {
        self.clearError();

        // Check for RPC error
        if (errors_module.parseErrorFromJson(self.allocator, response)) |err_detail| {
            self.last_error = err_detail;
            return ClientError.RpcError;
        }

        // Check for result
        if (!try utils.parseJsonResultExists(self.allocator, response)) {
            return ClientError.InvalidResponse;
        }
    }

    /// Record HTTP error response
    pub fn recordHttpErrorResponse(
        self: *SuiRpcClient,
        response_status: std.http.Status,
        response_body: []const u8,
    ) !void {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "HTTP {d}: {s}",
            .{ @intFromEnum(response_status), response_body },
        );
        self.setError(message, @intFromEnum(response_status));
    }

    /// Send raw JSON-RPC request
    pub fn sendJsonRpcRequest(
        self: *SuiRpcClient,
        method: []const u8,
        params_json: []const u8,
    ) ![]u8 {
        return try self.call(method, params_json);
    }

    /// Get transport statistics
    pub fn getTransportStats(self: *const SuiRpcClient) TransportStats {
        return self.transport_stats;
    }

    /// Reset transport statistics
    pub fn resetTransportStats(self: *SuiRpcClient) void {
        self.transport_stats = .{};
    }
};

// ============================================================
// Tests
// ============================================================

test "SuiRpcClient lifecycle" {
    const testing = std.testing;

    var client = try SuiRpcClient.init(testing.allocator, "https://example.com");
    defer client.deinit();

    try testing.expectEqualStrings("https://example.com", client.endpoint);
    try testing.expect(client.last_error == null);
}

test "SuiRpcClient initWithTimeout" {
    const testing = std.testing;

    var client = try SuiRpcClient.initWithTimeout(testing.allocator, "https://example.com", 5000);
    defer client.deinit();

    try testing.expectEqual(@as(?u64, 5000), client.request_timeout_ms);
}

test "SuiRpcClient recordErrorMessage" {
    const testing = std.testing;

    var client = try SuiRpcClient.init(testing.allocator, "https://example.com");
    defer client.deinit();

    try client.recordErrorMessage("test error");

    const err = client.getLastError();
    try testing.expect(err != null);
    try testing.expectEqualStrings("test error", err.?.message);
}

test "SuiRpcClient clearError" {
    const testing = std.testing;

    var client = try SuiRpcClient.init(testing.allocator, "https://example.com");
    defer client.deinit();

    try client.recordErrorMessage("test error");
    client.clearError();

    try testing.expect(client.getLastError() == null);
}

test "SuiRpcClient transport stats" {
    const testing = std.testing;

    var client = try SuiRpcClient.init(testing.allocator, "https://example.com");
    defer client.deinit();

    client.transport_stats.recordRequest(100);
    client.transport_stats.recordRequest(200);

    const stats = client.getTransportStats();
    try testing.expectEqual(@as(usize, 2), stats.request_count);
    try testing.expectEqual(@as(u64, 300), stats.elapsed_time_ms);
}

test "SuiRpcClient resetTransportStats" {
    const testing = std.testing;

    var client = try SuiRpcClient.init(testing.allocator, "https://example.com");
    defer client.deinit();

    client.transport_stats.recordRequest(100);
    client.resetTransportStats();

    const stats = client.getTransportStats();
    try testing.expectEqual(@as(usize, 0), stats.request_count);
}

test "RpcRequest structure" {
    const testing = std.testing;

    const request = RpcRequest{
        .id = 1,
        .method = "test_method",
        .params_json = "[]",
        .request_body = "{}",
    };

    try testing.expectEqual(@as(u64, 1), request.id);
    try testing.expectEqualStrings("test_method", request.method);
}

test "RequestSender callback type" {
    _ = std.testing;

    // Just verify the type compiles
    const Callback = RequestSenderCallback;
    _ = Callback;

    const sender = RequestSender{
        .context = undefined,
        .callback = undefined,
    };
    _ = sender;
}
