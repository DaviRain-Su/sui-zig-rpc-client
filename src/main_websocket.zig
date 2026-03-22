// WebSocket command implementation
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn cmdWebsocket(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printUsage();
        return;
    }

    const action = args[0];

    if (std.mem.eql(u8, action, "demo")) {
        try cmdWebsocketDemo(allocator);
    } else if (std.mem.eql(u8, action, "connect")) {
        if (args.len < 2) {
            std.log.err("Usage: websocket connect <endpoint>", .{});
            std.process.exit(1);
        }
        try cmdWebsocketConnect(allocator, args[1]);
    } else if (std.mem.eql(u8, action, "subscribe")) {
        try cmdWebsocketSubscribe(allocator, args[2..]);
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.log.info("Usage: websocket <action>", .{});
    std.log.info("Actions:", .{});
    std.log.info("  demo                      Demonstrate WebSocket functionality", .{});
    std.log.info("  connect <endpoint>        Connect to WebSocket endpoint", .{});
    std.log.info("  subscribe <filter>        Subscribe to events", .{});
}

fn cmdWebsocketDemo(allocator: Allocator) !void {
    _ = allocator;

    std.log.info("=== WebSocket Demo ===", .{});
    std.log.info("", .{});
    std.log.info("WebSocket support enables real-time event streaming:", .{});
    std.log.info("", .{});
    std.log.info("Features:", .{});
    std.log.info("  ✓ Real-time event subscriptions", .{});
    std.log.info("  ✓ Transaction notifications", .{});
    std.log.info("  ✓ Checkpoint updates", .{});
    std.log.info("  ✓ Bidirectional communication", .{});
    std.log.info("", .{});
    std.log.info("Use cases:", .{});
    std.log.info("  - Monitor address activity", .{});
    std.log.info("  - Track transaction status", .{});
    std.log.info("  - Receive instant confirmations", .{});
    std.log.info("  - Build real-time dashboards", .{});
    std.log.info("", .{});
    std.log.info("Example:", .{});
    std.log.info("  sui-zig websocket connect wss://fullnode.mainnet.sui.io", .{});
    std.log.info("  sui-zig websocket subscribe --address 0x123...", .{});
}

fn cmdWebsocketConnect(allocator: Allocator, endpoint: []const u8) !void {
    std.log.info("=== WebSocket Connection ===", .{});
    std.log.info("", .{});
    std.log.info("Endpoint: {s}", .{endpoint});
    std.log.info("", .{});

    // Import WebSocket module
    const WebSocketClient = @import("websocket.zig").WebSocketClient;

    var client = WebSocketClient.init(allocator);
    defer client.deinit();

    std.log.info("Connecting...", .{});

    // Attempt connection (will fail without actual server)
    client.connect(endpoint) catch |err| {
        std.log.info("Connection result: {s}", .{@errorName(err)});
        std.log.info("", .{});
        std.log.info("Note: This is a demonstration.", .{});
        std.log.info("For production use, ensure:", .{});
        std.log.info("  - Valid WebSocket endpoint", .{});
        std.log.info("  - Network connectivity", .{});
        std.log.info("  - Proper TLS certificates (for wss://)", .{});
        return;
    };

    std.log.info("Connected successfully!", .{});

    // Send test message
    try client.sendText("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_getVersion\"}");
    std.log.info("Sent: version request", .{});

    // Receive response
    const response = try client.receive();
    std.log.info("Received: {s}", .{response});
}

fn cmdWebsocketSubscribe(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    std.log.info("=== Event Subscription ===", .{});
    std.log.info("", .{});
    std.log.info("Subscription types:", .{});
    std.log.info("  - events: Move events", .{});
    std.log.info("  - transactions: Transaction effects", .{});
    std.log.info("  - checkpoints: New checkpoints", .{});
    std.log.info("", .{});
    std.log.info("Example filters:", .{});
    std.log.info("  --sender 0x123...          Filter by sender", .{});
    std.log.info("  --package 0x2              Filter by package", .{});
    std.log.info("  --module sui               Filter by module", .{});
    std.log.info("  --event-type Transfer      Filter by event type", .{});
}
