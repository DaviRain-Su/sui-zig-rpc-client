const builtin = @import("builtin");
const std = @import("std");

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

fn executeRequest(
    self: anytype,
    request_body: []const u8,
    response_writer: *std.io.Writer.Allocating,
    headers: []const std.http.Header,
) !std.http.Status {
    const uri = try std.Uri.parse(self.endpoint);
    var request = try self.http_client.request(.POST, uri, .{
        .redirect_behavior = .unhandled,
        .extra_headers = headers,
        .keep_alive = true,
    });
    defer request.deinit();

    try configureConnectionTimeouts(request.connection.?, self.request_timeout_ms);

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

    while (true) {
        attempts += 1;
        const request_start = std.time.milliTimestamp();

        response_status = executeRequest(self, request_body, &response_writer, &headers) catch |err| {
            const mapped_err = mapTimeoutError(err);
            if (mapped_err == error.Timeout) return error.Timeout;
            if (isRetryableTransportError(mapped_err)) {
                response_writer.deinit();
                response_writer = std.io.Writer.Allocating.init(self.allocator);

                self.http_client.deinit();
                self.http_client = .{ .allocator = self.allocator };
                continue;
            }
            return mapped_err;
        };

        const elapsed_ms = std.time.milliTimestamp() - request_start;
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
        return switch (response_status) {
            .request_timeout => error.Timeout,
            else => error.HttpError,
        };
    }

    return try response_writer.toOwnedSlice();
}
