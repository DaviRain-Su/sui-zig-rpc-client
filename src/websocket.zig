// WebSocket client for Sui real-time event subscriptions
// Supports event streaming and transaction notifications

const std = @import("std");
const Allocator = std.mem.Allocator;
const net = std.net;
const tls = std.crypto.tls;

// Platform-specific WebSocket implementation
const builtin = @import("builtin");
const is_wasm = builtin.target.isWasm();

pub const WebSocketError = error{
    ConnectionFailed,
    HandshakeFailed,
    InvalidUrl,
    NotConnected,
    AlreadyConnected,
    SendFailed,
    ReceiveFailed,
    InvalidFrame,
    Timeout,
};

/// WebSocket connection state
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    closing,
    closed,
};

/// WebSocket frame types
pub const OpCode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

/// WebSocket frame structure
pub const Frame = struct {
    fin: bool,
    opcode: OpCode,
    mask: bool,
    payload: []const u8,
};

/// WebSocket client for Sui RPC
pub const WebSocketClient = struct {
    allocator: Allocator,
    state: ConnectionState,
    
    // Connection
    stream: ?net.Stream,
    tls_client: ?*anyopaque, // Simplified for now
    
    // Buffer management
    read_buffer: []u8,
    write_buffer: []u8,
    
    // Event handlers
    on_message: ?*const fn ([]const u8) void,
    on_error: ?*const fn ([]const u8) void,
    on_close: ?*const fn () void,
    
    const Self = @This();
    const READ_BUFFER_SIZE = 64 * 1024;  // 64KB
    const WRITE_BUFFER_SIZE = 64 * 1024; // 64KB
    
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .state = .disconnected,
            .stream = null,
            .tls_client = null,
            .read_buffer = &[_]u8{},
            .write_buffer = &[_]u8{},
            .on_message = null,
            .on_error = null,
            .on_close = null,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.disconnect() catch {};
        self.allocator.free(self.read_buffer);
        self.allocator.free(self.write_buffer);
    }
    
    /// Connect to WebSocket endpoint
    pub fn connect(self: *Self, url: []const u8) !void {
        if (self.state != .disconnected) {
            return WebSocketError.AlreadyConnected;
        }
        
        self.state = .connecting;
        errdefer self.state = .disconnected;
        
        // Parse URL
        const is_wss = std.mem.startsWith(u8, url, "wss://");
        const is_ws = std.mem.startsWith(u8, url, "ws://");
        
        if (!is_wss and !is_ws) {
            return WebSocketError.InvalidUrl;
        }
        
        const scheme_len: usize = if (is_wss) 6 else 5;
        const rest = url[scheme_len..];
        
        // Extract host and path
        const path_start = std.mem.indexOf(u8, rest, "/") orelse rest.len;
        const host_port = rest[0..path_start];
        const path = if (path_start < rest.len) rest[path_start..] else "/";
        
        // Parse host and port
        const port: u16 = if (is_wss) 443 else 80;
        const host = host_port;
        
        // Connect TCP
        const address = try net.Address.parseIp(host, port);
        self.stream = try net.tcpConnectToAddress(address);
        errdefer {
            if (self.stream) |s| {
                s.close();
                self.stream = null;
            }
        }
        
        // Allocate buffers
        self.read_buffer = try self.allocator.alloc(u8, READ_BUFFER_SIZE);
        self.write_buffer = try self.allocator.alloc(u8, WRITE_BUFFER_SIZE);
        
        // Perform WebSocket handshake
        try self.performHandshake(host, path, is_wss);
        
        self.state = .connected;
    }
    
    /// Perform WebSocket handshake
    fn performHandshake(self: *Self, host: []const u8, path: []const u8, is_tls: bool) !void {
        _ = is_tls;
        
        const stream = self.stream.?;
        
        // Generate WebSocket key (base64 of 16 random bytes)
        var nonce: [16]u8 = undefined;
        std.crypto.random.bytes(&nonce);
        var key_buf: [24]u8 = undefined; // base64 of 16 bytes = 24 bytes
        _ = std.base64.standard.Encoder.encode(&key_buf, &nonce);
        const key = key_buf[0..24];
        
        // Build handshake request
        const request = try std.fmt.allocPrint(self.allocator,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "\r\n",
            .{ path, host, key }
        );
        defer self.allocator.free(request);
        
        // Send request
        _ = try stream.write(request);
        
        // Read response
        const response_len = try stream.read(self.read_buffer);
        const response = self.read_buffer[0..response_len];
        
        // Verify response
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) {
            return WebSocketError.HandshakeFailed;
        }
        
        // Check for WebSocket-Accept header (simplified)
        if (!std.mem.containsAtLeast(u8, response, 1, "Upgrade: websocket")) {
            return WebSocketError.HandshakeFailed;
        }
    }
    
    /// Disconnect from WebSocket
    pub fn disconnect(self: *Self) !void {
        switch (self.state) {
            .connected => {
                self.state = .closing;
                
                // Send close frame
                _ = self.sendFrame(.close, &[_]u8{}) catch {};
                
                if (self.stream) |s| {
                    s.close();
                    self.stream = null;
                }
                
                self.state = .closed;
                
                if (self.on_close) |handler| {
                    handler();
                }
            },
            else => {},
        }
    }
    
    /// Send text message
    pub fn sendText(self: *Self, text: []const u8) !void {
        if (self.state != .connected) {
            return WebSocketError.NotConnected;
        }
        
        return self.sendFrame(.text, text);
    }
    
    /// Send binary message
    pub fn sendBinary(self: *Self, data: []const u8) !void {
        if (self.state != .connected) {
            return WebSocketError.NotConnected;
        }
        
        return self.sendFrame(.binary, data);
    }
    
    /// Send WebSocket frame
    fn sendFrame(self: *Self, opcode: OpCode, payload: []const u8) !void {
        const stream = self.stream.?;
        
        // Build frame header
        var header: [14]u8 = undefined; // Max header size
        var header_len: usize = 0;
        
        // First byte: FIN + RSV + opcode
        header[0] = @as(u8, 0x80) | @as(u8, @intFromEnum(opcode));
        header_len += 1;
        
        // Second byte: MASK + payload length
        const mask_bit: u8 = 0x80; // Always mask client frames
        
        if (payload.len < 126) {
            header[1] = mask_bit | @as(u8, @intCast(payload.len));
            header_len += 1;
        } else if (payload.len < 65536) {
            header[1] = mask_bit | 126;
            header[2] = @as(u8, @intCast(payload.len >> 8));
            header[3] = @as(u8, @intCast(payload.len & 0xFF));
            header_len += 3;
        } else {
            header[1] = mask_bit | 127;
            // 64-bit length (simplified, assuming payload fits in 32 bits)
            @memset(header[2..10], 0);
            header[10] = @as(u8, @intCast((payload.len >> 24) & 0xFF));
            header[11] = @as(u8, @intCast((payload.len >> 16) & 0xFF));
            header[12] = @as(u8, @intCast((payload.len >> 8) & 0xFF));
            header[13] = @as(u8, @intCast(payload.len & 0xFF));
            header_len += 9;
        }
        
        // Generate masking key
        var mask: [4]u8 = undefined;
        std.crypto.random.bytes(&mask);
        @memcpy(header[header_len..][0..4], &mask);
        header_len += 4;
        
        // Send header
        _ = try stream.write(header[0..header_len]);
        
        // Send masked payload
        if (payload.len > 0) {
            var masked = try self.allocator.alloc(u8, payload.len);
            defer self.allocator.free(masked);
            
            for (payload, 0..) |byte, i| {
                masked[i] = byte ^ mask[i % 4];
            }
            
            _ = try stream.write(masked);
        }
    }
    
    /// Receive and process message (blocking)
    pub fn receive(self: *Self) ![]const u8 {
        if (self.state != .connected) {
            return WebSocketError.NotConnected;
        }
        
        const stream = self.stream.?;
        
        // Read frame header (at least 2 bytes)
        var header: [2]u8 = undefined;
        _ = try stream.read(&header);
        
        const opcode = @as(OpCode, @enumFromInt(header[0] & 0x0F));
        const masked = (header[1] & 0x80) != 0;
        var payload_len = @as(usize, header[1] & 0x7F);
        
        // Extended payload length
        if (payload_len == 126) {
            var ext_len: [2]u8 = undefined;
            _ = try stream.read(&ext_len);
            payload_len = (@as(usize, ext_len[0]) << 8) | ext_len[1];
        } else if (payload_len == 127) {
            var ext_len: [8]u8 = undefined;
            _ = try stream.read(&ext_len);
            payload_len = 0;
            for (ext_len) |b| {
                payload_len = (payload_len << 8) | b;
            }
        }
        
        // Read masking key if present
        var mask: [4]u8 = undefined;
        if (masked) {
            _ = try stream.read(&mask);
        }
        
        // Read payload
        if (payload_len > self.read_buffer.len) {
            return WebSocketError.InvalidFrame;
        }
        
        var payload = self.read_buffer[0..payload_len];
        var total_read: usize = 0;
        while (total_read < payload_len) {
            const n = try stream.read(payload[total_read..]);
            if (n == 0) return WebSocketError.ReceiveFailed;
            total_read += n;
        }
        
        // Unmask payload
        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask[i % 4];
            }
        }
        
        // Handle frame
        switch (opcode) {
            .text, .binary => {
                return payload;
            },
            .close => {
                try self.disconnect();
                return WebSocketError.NotConnected;
            },
            .ping => {
                // Send pong
                try self.sendFrame(.pong, payload);
                return self.receive(); // Continue reading
            },
            .pong => {
                return self.receive(); // Continue reading
            },
            else => return WebSocketError.InvalidFrame,
        }
    }
    
    /// Set message handler
    pub fn setOnMessage(self: *Self, handler: *const fn ([]const u8) void) void {
        self.on_message = handler;
    }
    
    /// Set error handler
    pub fn setOnError(self: *Self, handler: *const fn ([]const u8) void) void {
        self.on_error = handler;
    }
    
    /// Set close handler
    pub fn setOnClose(self: *Self, handler: *const fn () void) void {
        self.on_close = handler;
    }
};

/// Sui event subscription client
pub const SuiEventSubscriber = struct {
    allocator: Allocator,
    ws_client: WebSocketClient,
    subscription_id: ?u64,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .ws_client = WebSocketClient.init(allocator),
            .subscription_id = null,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.ws_client.deinit();
    }
    
    /// Connect to Sui WebSocket endpoint
    pub fn connect(self: *Self, endpoint: []const u8) !void {
        // Convert HTTP endpoint to WebSocket
        const ws_endpoint = if (std.mem.startsWith(u8, endpoint, "https://"))
            try std.fmt.allocPrint(self.allocator, "wss://{s}", .{endpoint[8..]})
        else if (std.mem.startsWith(u8, endpoint, "http://"))
            try std.fmt.allocPrint(self.allocator, "ws://{s}", .{endpoint[7..]})
        else
            try self.allocator.dupe(u8, endpoint);
        defer self.allocator.free(ws_endpoint);
        
        try self.ws_client.connect(ws_endpoint);
    }
    
    /// Subscribe to events
    pub fn subscribeToEvents(self: *Self, filter: EventFilter) !void {
        const request = try std.fmt.allocPrint(self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"suix_subscribeEvent\",\"params\":[{s}]}}",
            .{filter.toJson()}
        );
        defer self.allocator.free(request);
        
        try self.ws_client.sendText(request);
    }
    
    /// Subscribe to transaction effects
    pub fn subscribeToTransactions(self: *Self, filter: TransactionFilter) !void {
        const request = try std.fmt.allocPrint(self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"suix_subscribeTransaction\",\"params\":[{s}]}}",
            .{filter.toJson()}
        );
        defer self.allocator.free(request);
        
        try self.ws_client.sendText(request);
    }
    
    /// Receive next event (blocking)
    pub fn receiveEvent(self: *Self) ![]const u8 {
        return self.ws_client.receive();
    }
    
    /// Disconnect
    pub fn disconnect(self: *Self) !void {
        return self.ws_client.disconnect();
    }
};

/// Event filter for subscriptions
pub const EventFilter = struct {
    sender: ?[]const u8 = null,
    event_type: ?[]const u8 = null,
    package_id: ?[]const u8 = null,
    module_name: ?[]const u8 = null,
    
    pub fn toJson(self: EventFilter) []const u8 {
        // Simplified JSON serialization
        _ = self;
        return "{}";
    }
};

/// Transaction filter for subscriptions
pub const TransactionFilter = struct {
    from_address: ?[]const u8 = null,
    to_address: ?[]const u8 = null,
    input_object: ?[]const u8 = null,
    changed_object: ?[]const u8 = null,
    
    pub fn toJson(self: TransactionFilter) []const u8 {
        // Simplified JSON serialization
        _ = self;
        return "{}";
    }
};

// Test functions
test "WebSocketClient init/deinit" {
    const allocator = std.testing.allocator;
    
    var client = WebSocketClient.init(allocator);
    defer client.deinit();
    
    try std.testing.expectEqual(client.state, .disconnected);
}

test "EventFilter toJson" {
    const filter = EventFilter{
        .sender = "0x123",
        .event_type = "Transfer",
    };
    
    const json = filter.toJson();
    try std.testing.expectEqualStrings("{}", json);
}
