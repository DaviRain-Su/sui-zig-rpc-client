/// client/rpc_client/examples.zig - Usage examples for RPC client
const std = @import("std");
const rpc_client = @import("root.zig");

const SuiRpcClient = rpc_client.SuiRpcClient;
const ClientError = rpc_client.ClientError;

/// Example: Basic client initialization
/// ```zig
/// var client = try SuiRpcClient.init(allocator, "https://fullnode.mainnet.sui.io");
/// defer client.deinit();
/// ```
pub fn exampleBasicClient(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Example: Basic Client ===\n", .{});

    // Initialize client with mainnet endpoint
    var client = try SuiRpcClient.init(allocator, rpc_client.default_mainnet_endpoint);
    defer client.deinit();

    std.debug.print("Client initialized with endpoint: {s}\n", .{client.endpoint});
}

/// Example: Query balance
/// ```zig
/// const balance = try rpc_client.getBalance(&client, address, null);
/// ```
pub fn exampleQueryBalance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Query Balance ===\n", .{});

    var client = try SuiRpcClient.init(allocator, rpc_client.default_mainnet_endpoint);
    defer client.deinit();

    const address = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

    // Query SUI balance
    const balance = rpc_client.getBalance(&client, address, null);

    if (balance) |bal| {
        const sui = rpc_client.mistToSui(bal);
        std.debug.print("Balance: {d} MIST ({d} SUI)\n", .{ bal, sui });
    } else |err| {
        std.debug.print("Error querying balance: {any}\n", .{err});
    }
}

/// Example: Query all balances
/// ```zig
/// const balances = try rpc_client.getAllBalances(&client, address);
/// ```
pub fn exampleQueryAllBalances(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Query All Balances ===\n", .{});

    var client = try SuiRpcClient.init(allocator, rpc_client.default_mainnet_endpoint);
    defer client.deinit();

    const address = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

    const balances = rpc_client.getAllBalances(&client, address);

    if (balances) |bal_list| {
        defer {
            for (bal_list) |*b| b.deinit(allocator);
            allocator.free(bal_list);
        }

        std.debug.print("Found {d} coin types:\n", .{bal_list.len});
        for (bal_list) |bal| {
            std.debug.print("  {s}: {d}\n", .{ bal.coin_type, bal.total_balance });
        }
    } else |err| {
        std.debug.print("Error querying balances: {any}\n", .{err});
    }
}

/// Example: Query object
/// ```zig
/// const obj = try rpc_client.getObject(&client, object_id, options);
/// ```
pub fn exampleQueryObject(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Query Object ===\n", .{});

    var client = try SuiRpcClient.init(allocator, rpc_client.default_mainnet_endpoint);
    defer client.deinit();

    const object_id = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

    // Query with options
    const options = rpc_client.ObjectDataOptions{
        .show_type = true,
        .show_content = true,
        .show_owner = true,
    };

    const obj = rpc_client.getObject(&client, object_id, options);

    if (obj) |object| {
        defer object.deinit(allocator);
        std.debug.print("Object ID: {s}\n", .{object.object_id});
        std.debug.print("Version: {d}\n", .{object.version});
        if (object.type) |t| {
            std.debug.print("Type: {s}\n", .{t});
        }
    } else |err| {
        std.debug.print("Error querying object: {any}\n", .{err});
    }
}

/// Example: Query events
/// ```zig
/// const filter = rpc_client.EventFilter{ .all = {} };
/// const page = try rpc_client.queryEvents(&client, filter, null, 10, false);
/// ```
pub fn exampleQueryEvents(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Query Events ===\n", .{});

    var client = try SuiRpcClient.init(allocator, rpc_client.default_mainnet_endpoint);
    defer client.deinit();

    // Query all events
    const filter = rpc_client.EventFilter{ .all = {} };

    const page = rpc_client.queryEvents(&client, filter, null, 10, false);

    if (page) |event_page| {
        defer event_page.deinit(allocator);

        std.debug.print("Found {d} events:\n", .{event_page.data.len});
        for (event_page.data) |event| {
            std.debug.print("  Type: {s}, Package: {s}\n", .{ event.type, event.package_id });
        }

        if (event_page.has_next_page) {
            std.debug.print("More events available...\n", .{});
        }
    } else |err| {
        std.debug.print("Error querying events: {any}\n", .{err});
    }
}

/// Example: Query Move module
/// ```zig
/// const module_def = try rpc_client.getNormalizedMoveModule(&client, package_id, module_name);
/// ```
pub fn exampleQueryMoveModule(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Query Move Module ===\n", .{});

    var client = try SuiRpcClient.init(allocator, rpc_client.default_mainnet_endpoint);
    defer client.deinit();

    const package_id = "0x2";
    const module_name = "sui";

    const module_def = rpc_client.getNormalizedMoveModule(&client, package_id, module_name);

    if (module_def) |mod| {
        defer mod.deinit(allocator);

        std.debug.print("Module: {s}@{s}\n", .{ mod.name, mod.address });
        std.debug.print("File format version: {d}\n", .{mod.file_format_version});
        std.debug.print("Structs: {d}\n", .{mod.structs.len});
        std.debug.print("Exposed functions: {d}\n", .{mod.exposed_functions.len});
    } else |err| {
        std.debug.print("Error querying module: {any}\n", .{err});
    }
}

/// Example: Using mock sender for testing
/// ```zig
/// var mock = MockSender.init(allocator);
/// client.setRequestSender(.{ .context = &mock, .callback = MockSender.senderCallback });
/// ```
pub fn exampleMockSender(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Mock Sender ===\n", .{});

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    // Create mock sender
    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    // Add mock responses
    try mock.addResponse("suix_getBalance", "{\"result\":{\"coinType\":\"0x2::sui::SUI\",\"coinObjectCount\":5,\"totalBalance\":\"1000000000\",\"lockedBalance\":{}}}");

    // Set mock sender
    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    // Now calls will use mock responses
    const balance = try rpc_client.getBalance(&client, "0x123", null);
    std.debug.print("Mock balance: {d} MIST\n", .{balance});
}

/// Mock sender for examples
const MockSender = struct {
    responses: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) MockSender {
        return .{
            .responses = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MockSender, allocator: std.mem.Allocator) void {
        var it = self.responses.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.responses.deinit();
    }

    pub fn addResponse(self: *MockSender, method: []const u8, response: []const u8) !void {
        const key = try self.responses.allocator.dupe(u8, method);
        const value = try self.responses.allocator.dupe(u8, response);
        try self.responses.put(key, value);
    }

    pub fn senderCallback(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        request: rpc_client.RpcRequest,
    ) std.mem.Allocator.Error![]u8 {
        const self = @as(*MockSender, @ptrCast(@alignCast(context)));

        if (self.responses.get(request.method)) |response| {
            return try allocator.dupe(u8, response);
        }

        return try allocator.dupe(u8, "{\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}");
    }
};

/// Example: Error handling
/// ```zig
/// const result = rpc_client.getBalance(&client, address, null);
/// if (result) |balance| { ... } else |err| { ... }
/// ```
pub fn exampleErrorHandling(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Error Handling ===\n", .{});

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    // Invalid address
    const result = rpc_client.getBalance(&client, "invalid", null);

    if (result) |balance| {
        std.debug.print("Balance: {d}\n", .{balance});
    } else |err| {
        switch (err) {
            ClientError.InvalidResponse => std.debug.print("Invalid response or parameters\n", .{}),
            ClientError.RpcError => std.debug.print("RPC error: {s}\n", .{client.getLastError().?.message}),
            ClientError.HttpError => std.debug.print("HTTP error\n", .{}),
            else => std.debug.print("Other error: {any}\n", .{err}),
        }
    }
}

/// Example: Transport statistics
/// ```zig
/// const stats = client.getTransportStats();
/// std.debug.print("Requests: {d}, Time: {d}ms\n", .{ stats.request_count, stats.elapsed_time_ms });
/// ```
pub fn exampleTransportStats(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Example: Transport Statistics ===\n", .{});

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    // Set up mock
    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);
    try mock.addResponse("test", "{\"result\":{}}");

    client.setRequestSender(.{
        .context = &mock,
        .callback = MockSender.senderCallback,
    });

    // Make some requests
    for (0..5) |_| {
        const resp = try client.call("test", "[]");
        allocator.free(resp);
    }

    // Get stats
    const stats = client.getTransportStats();
    std.debug.print("Total requests: {d}\n", .{stats.request_count});
    std.debug.print("Total time: {d}ms\n", .{stats.elapsed_time_ms});
    if (stats.request_count > 0) {
        const avg = stats.elapsed_time_ms / stats.request_count;
        std.debug.print("Average time: {d}ms\n", .{avg});
    }
}

/// Run all examples
pub fn runAllExamples(allocator: std.mem.Allocator) !void {
    try exampleBasicClient(allocator);
    try exampleQueryBalance(allocator);
    try exampleQueryAllBalances(allocator);
    try exampleQueryObject(allocator);
    try exampleQueryEvents(allocator);
    try exampleQueryMoveModule(allocator);
    try exampleMockSender(allocator);
    try exampleErrorHandling(allocator);
    try exampleTransportStats(allocator);
}
