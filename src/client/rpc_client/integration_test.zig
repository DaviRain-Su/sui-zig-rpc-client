/// client/rpc_client/integration_test.zig - Integration tests for RPC client
const std = @import("std");
const rpc_client = @import("root.zig");

const SuiRpcClient = rpc_client.SuiRpcClient;
const ClientError = rpc_client.ClientError;

// Mock request sender for testing
const MockSender = struct {
    responses: std.StringHashMap([]const u8),
    request_log: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) MockSender {
        return .{
            .responses = std.StringHashMap([]const u8).init(allocator),
            .request_log = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MockSender, allocator: std.mem.Allocator) void {
        var it = self.responses.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.responses.deinit();
        for (self.request_log.items) |req| {
            allocator.free(req);
        }
        self.request_log.deinit();
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
        
        const logged = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ request.method, request.params_json });
        try self.request_log.append(logged);
        
        if (self.responses.get(request.method)) |response| {
            return try allocator.dupe(u8, response);
        }
        
        return try allocator.dupe(u8, "{\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}");
    }
};

// Test client with mock sender
test "SuiRpcClient with mock sender" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("test_method", "{\"result\":{\"data\":\"test\"}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const response = try client.call("test_method", "[]");
    defer allocator.free(response);

    try testing.expect(std.mem.containsAtLeast(u8, response, 1, "test"));
    try testing.expectEqual(@as(usize, 1), mock.request_log.items.len);
}

// Test error handling
test "SuiRpcClient error handling" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("error_method", "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const result = client.call("error_method", "[]");
    try testing.expectError(ClientError.RpcError, result);

    const last_error = client.getLastError();
    try testing.expect(last_error != null);
    try testing.expectEqual(@as(i64, -32600), last_error.?.code.?);
}

// Test balance query flow
test "getBalance integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("suix_getBalance", 
        "{\"result\":{\"coinType\":\"0x2::sui::SUI\",\"coinObjectCount\":5,\"totalBalance\":\"1000000000\",\"lockedBalance\":{}}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const balance = try rpc_client.getBalance(&client, "0x123", null);
    try testing.expectEqual(@as(u64, 1000000000), balance);
}

// Test object query flow
test "getObject integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("sui_getObject",
        "{\"result\":{\"data\":{\"objectId\":\"0x123\",\"version\":\"1\",\"digest\":\"abc\",\"type\":\"0x2::coin::Coin\"}}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const obj = try rpc_client.getObject(&client, "0x123", null);
    defer obj.deinit(allocator);

    try testing.expectEqualStrings("0x123", obj.object_id);
    try testing.expectEqual(@as(u64, 1), obj.version);
}

// Test gas price query
test "getReferenceGasPrice integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("suix_getReferenceGasPrice", "{\"result\":\"1000\"}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const gas_price = try rpc_client.getReferenceGasPrice(&client);
    try testing.expectEqual(@as(u64, 1000), gas_price);
}

// Test event query flow
test "queryEvents integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("suix_queryEvents",
        "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xabc\",\"eventSeq\":0},\"packageId\":\"0x2\",\"transactionModule\":\"sui\",\"sender\":\"0x123\",\"type\":\"0x2::event::Event\",\"bcs\":\"0x00\"}],\"hasNextPage\":false}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const filter = rpc_client.EventFilter{ .all = {} };
    const page = try rpc_client.queryEvents(&client, filter, null, 10, false);
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.data.len);
    try testing.expect(!page.has_next_page);
}

// Test Move module query
test "getNormalizedMoveModule integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("sui_getNormalizedMoveModule",
        "{\"result\":{\"fileFormatVersion\":6,\"address\":\"0x2\",\"name\":\"sui\",\"friends\":[],\"structs\":{},\"exposedFunctions\":{}}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const module_def = try rpc_client.getNormalizedMoveModule(&client, "0x2", "sui");
    defer module_def.deinit(allocator);

    try testing.expectEqualStrings("0x2", module_def.address);
    try testing.expectEqualStrings("sui", module_def.name);
}

// Test multiple sequential calls
test "sequential calls integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("method1", "{\"result\":\"response1\"}");
    try mock.addResponse("method2", "{\"result\":\"response2\"}");
    try mock.addResponse("method3", "{\"result\":\"response3\"}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const resp1 = try client.call("method1", "[]");
    defer allocator.free(resp1);
    const resp2 = try client.call("method2", "[]");
    defer allocator.free(resp2);
    const resp3 = try client.call("method3", "[]");
    defer allocator.free(resp3);

    try testing.expectEqual(@as(usize, 3), mock.request_log.items.len);
}

// Test transport stats accumulation
test "transport stats accumulation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("test", "{\"result\":{}}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    // Simulate multiple requests
    for (0..5) |_| {
        const resp = try client.call("test", "[]");
        allocator.free(resp);
    }

    const stats = client.getTransportStats();
    try testing.expectEqual(@as(usize, 5), stats.request_count);
}

// Test error recovery
test "error recovery after failed call" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("fail", "{\"error\":{\"code\":-1,\"message\":\"fail\"}}");
    try mock.addResponse("success", "{\"result\":\"ok\"}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    // First call fails
    const result1 = client.call("fail", "[]");
    try testing.expectError(ClientError.RpcError, result1);

    // Second call succeeds
    const result2 = try client.call("success", "[]");
    defer allocator.free(result2);

    // Error should be cleared
    try testing.expect(client.getLastError() == null);
}

// Test invalid address handling
test "invalid address handling" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    const result = rpc_client.getBalance(&client, "invalid_address", null);
    try testing.expectError(ClientError.InvalidResponse, result);
}

// Test empty response handling
test "empty response handling" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try SuiRpcClient.init(allocator, "http://mock");
    defer client.deinit();

    var mock = MockSender.init(allocator);
    defer mock.deinit(allocator);

    try mock.addResponse("empty", "{\"result\":null}");

    const sender = rpc_client.RequestSender{
        .context = &mock,
        .callback = MockSender.senderCallback,
    };
    client.setRequestSender(sender);

    const result = client.call("empty", "[]");
    try testing.expectError(ClientError.InvalidResponse, result);
}
