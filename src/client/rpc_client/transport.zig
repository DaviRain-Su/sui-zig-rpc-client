const builtin = @import("builtin");
const std = @import("std");
const retryable_transport_attempt_limit: usize = 3;

fn isRetryableTransportError(err: anyerror) bool {
    return switch (err) {
        error.HttpConnectionClosing,
        error.ConnectionResetByPeer,
        error.ReadFailed,
        => true,
        else => false,
    };
}

fn mapTimeoutError(err: anyerror) anyerror {
    return switch (err) {
        error.WouldBlock,
        error.ConnectionTimedOut,
        error.TimeoutTooBig,
        => error.Timeout,
        else => err,
    };
}

fn configureSocketTimeout(handle: std.net.Stream.Handle, timeout_ms: u64, option: u32) !void {
    if (builtin.os.tag == .windows) {
        var timeout: u32 = @intCast(@min(timeout_ms, std.math.maxInt(u32)));
        try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, option, std.mem.asBytes(&timeout));
        return;
    }

    var timeout = std.mem.zeroes(std.posix.timeval);
    timeout.sec = @intCast(timeout_ms / std.time.ms_per_s);
    timeout.usec = @intCast((timeout_ms % std.time.ms_per_s) * std.time.us_per_ms);
    try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, option, std.mem.asBytes(&timeout));
}

fn configureConnectionTimeouts(connection: *std.http.Client.Connection, timeout_ms: ?u64) !void {
    const value = timeout_ms orelse return;
    const handle = connection.stream_reader.getStream().handle;
    try configureSocketTimeout(handle, value, std.posix.SO.SNDTIMEO);
    try configureSocketTimeout(handle, value, std.posix.SO.RCVTIMEO);
}

fn remainingTimeoutMs(start_ms: i64, total_timeout_ms: ?u64) !?u64 {
    const timeout_ms = total_timeout_ms orelse return null;
    const timeout_i64 = std.math.cast(i64, timeout_ms) orelse std.math.maxInt(i64);
    const elapsed_ms = std.time.milliTimestamp() - start_ms;
    if (elapsed_ms >= timeout_i64) return error.Timeout;
    return @as(u64, @intCast(timeout_i64 - elapsed_ms));
}

fn executeRequest(
    self: anytype,
    request_body: []const u8,
    response_writer: *std.io.Writer.Allocating,
    headers: []const std.http.Header,
    timeout_ms: ?u64,
) !std.http.Status {
    const uri = try std.Uri.parse(self.endpoint);
    var request = try self.http_client.request(.POST, uri, .{
        .redirect_behavior = .unhandled,
        .extra_headers = headers,
        .keep_alive = true,
    });
    defer request.deinit();

    try configureConnectionTimeouts(request.connection.?, timeout_ms);

    request.transfer_encoding = .{ .content_length = request_body.len };
    request.sendBodyComplete(@constCast(request_body)) catch |err| return mapTimeoutError(err);

    var response = request.receiveHead(&.{}) catch |err| switch (err) {
        error.ReadFailed => {
            if (request.connection) |connection| {
                if (connection.getReadError()) |read_err| return mapTimeoutError(read_err);
            }
            return err;
        },
        else => return mapTimeoutError(err),
    };

    const decompress_buffer = switch (response.head.content_encoding) {
        .identity => null,
        .zstd => try self.allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try self.allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (decompress_buffer) |buffer| self.allocator.free(buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer orelse &.{});

    _ = reader.streamRemaining(&response_writer.writer) catch |err| switch (err) {
        error.ReadFailed => return mapTimeoutError(response.bodyErr().?),
        else => return mapTimeoutError(err),
    };

    return response.head.status;
}

pub fn sendRequest(self: anytype, method: []const u8, params_json: []const u8) ![]u8 {
    const request_id = self.request_id;
    const request_body = try std.fmt.allocPrint(
        self.allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"{s}\",\"params\":{s}}}",
        .{ request_id, method, params_json },
    );
    self.request_id +%= 1;

    if (self.request_sender) |sender| {
        defer self.allocator.free(request_body);
        self.transport_stats.request_count += 1;
        return sender.callback(sender.context, self.allocator, .{ .id = request_id, .method = method, .params_json = params_json, .request_body = request_body });
    }

    errdefer self.allocator.free(request_body);

    var response_writer = std.io.Writer.Allocating.init(self.allocator);
    errdefer response_writer.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
    };

    var response_status: std.http.Status = undefined;
    var attempts: usize = 0;
    const request_start_ms = std.time.milliTimestamp();

    while (true) {
        attempts += 1;
        const request_timeout_ms = try remainingTimeoutMs(request_start_ms, self.request_timeout_ms);
        const attempt_start_ms = std.time.milliTimestamp();

        response_status = executeRequest(self, request_body, &response_writer, &headers, request_timeout_ms) catch |err| {
            const mapped_err = mapTimeoutError(err);
            if (mapped_err == error.Timeout) return error.Timeout;
            if (isRetryableTransportError(mapped_err) and attempts < retryable_transport_attempt_limit) {
                _ = remainingTimeoutMs(request_start_ms, self.request_timeout_ms) catch return error.Timeout;
                response_writer.deinit();
                response_writer = std.io.Writer.Allocating.init(self.allocator);

                self.http_client.deinit();
                self.http_client = .{ .allocator = self.allocator };
                continue;
            }
            return mapped_err;
        };

        const elapsed_ms = std.time.milliTimestamp() - attempt_start_ms;
        if (elapsed_ms > 0) {
            self.transport_stats.elapsed_time_ms += @intCast(@max(elapsed_ms, 0));
            if (response_status == .too_many_requests) {
                self.transport_stats.rate_limited_time_ms += @intCast(@max(elapsed_ms, 0));
            }
        }

        break;
    }

    self.transport_stats.request_count += attempts;
    self.allocator.free(request_body);

    if (response_status != .ok) {
        const response_body = try response_writer.toOwnedSlice();
        defer self.allocator.free(response_body);
        if (@hasDecl(@TypeOf(self.*), "recordHttpErrorResponse")) {
            self.recordHttpErrorResponse(response_status, response_body) catch {};
        }
        return switch (response_status) {
            .request_timeout => error.Timeout,
            else => error.HttpError,
        };
    }

    return try response_writer.toOwnedSlice();
}
