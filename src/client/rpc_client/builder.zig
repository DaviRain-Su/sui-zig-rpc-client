/// client/rpc_client/builder.zig - Transaction building for Sui RPC Client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Move call parameters
pub const MoveCallParams = struct {
    /// Package address
    package: []const u8,
    /// Module name
    module: []const u8,
    /// Function name
    function: []const u8,
    /// Type arguments
    type_arguments: []const []const u8 = &.{},
    /// Function arguments
    arguments: []const []const u8 = &.{},
    /// Gas budget
    gas_budget: ?u64 = null,
    /// Gas price
    gas_price: ?u64 = null,

    pub fn deinit(self: *MoveCallParams, allocator: std.mem.Allocator) void {
        allocator.free(self.package);
        allocator.free(self.module);
        allocator.free(self.function);
        for (self.type_arguments) |ta| allocator.free(ta);
        allocator.free(self.type_arguments);
        for (self.arguments) |arg| allocator.free(arg);
        allocator.free(self.arguments);
    }
};

/// Build Move call transaction bytes
pub fn buildMoveCallTxBytes(
    client: *SuiRpcClient,
    sender: []const u8,
    params: MoveCallParams,
) ![]u8 {
    // Build the transaction kind JSON
    var tx_kind = std.json.ObjectMap.init(client.allocator);
    defer tx_kind.deinit();

    try tx_kind.put("kind", .{ .string = "moveCall" });
    try tx_kind.put("package", .{ .string = params.package });
    try tx_kind.put("module", .{ .string = params.module });
    try tx_kind.put("function", .{ .string = params.function });

    // Add type arguments
    var type_args = std.json.Array.init(client.allocator);
    defer type_args.deinit();
    for (params.type_arguments) |ta| {
        try type_args.append(.{ .string = ta });
    }
    try tx_kind.put("typeArguments", .{ .array = type_args });

    // Add arguments
    var args = std.json.Array.init(client.allocator);
    defer args.deinit();
    for (params.arguments) |arg| {
        try args.append(.{ .string = arg });
    }
    try tx_kind.put("arguments", .{ .array = args });

    // Build full transaction data
    var tx_data = std.json.ObjectMap.init(client.allocator);
    defer tx_data.deinit();

    try tx_data.put("sender", .{ .string = sender });
    try tx_data.put("txKind", .{ .object = tx_kind });
    
    if (params.gas_budget) |budget| {
        const budget_str = try std.fmt.allocPrint(client.allocator, "{d}", .{budget});
        defer client.allocator.free(budget_str);
        try tx_data.put("gasBudget", .{ .string = budget_str });
    }

    if (params.gas_price) |price| {
        const price_str = try std.fmt.allocPrint(client.allocator, "{d}", .{price});
        defer client.allocator.free(price_str);
        try tx_data.put("gasPrice", .{ .string = price_str });
    }

    // Serialize to JSON string
    const json_str = try std.json.stringifyAlloc(client.allocator, .{ .object = tx_data }, .{});
    defer client.allocator.free(json_str);

    // Call unsafe_batchTransaction to build tx bytes
    const params_json = try std.fmt.allocPrint(
        client.allocator,
        "[{s}]",
        .{json_str},
    );
    defer client.allocator.free(params_json);

    const response = try client.call("unsafe_batchTransaction", params_json);
    return response;
}

/// Batch transaction item
pub const BatchItem = union(enum) {
    move_call: MoveCallParams,
    transfer: TransferParams,
    split_coins: SplitCoinsParams,
    merge_coins: MergeCoinsParams,
};

/// Transfer parameters
pub const TransferParams = struct {
    /// Objects to transfer
    object_ids: []const []const u8,
    /// Recipient address
    recipient: []const u8,

    pub fn deinit(self: *TransferParams, allocator: std.mem.Allocator) void {
        for (self.object_ids) |id| allocator.free(id);
        allocator.free(self.object_ids);
        allocator.free(self.recipient);
    }
};

/// Split coins parameters
pub const SplitCoinsParams = struct {
    /// Coin object ID to split
    coin_object_id: []const u8,
    /// Amounts to split into
    amounts: []const u64,

    pub fn deinit(self: *SplitCoinsParams, allocator: std.mem.Allocator) void {
        allocator.free(self.coin_object_id);
        allocator.free(self.amounts);
    }
};

/// Merge coins parameters
pub const MergeCoinsParams = struct {
    /// Destination coin object ID
    destination: []const u8,
    /// Source coin object IDs to merge
    sources: []const []const u8,

    pub fn deinit(self: *MergeCoinsParams, allocator: std.mem.Allocator) void {
        allocator.free(self.destination);
        for (self.sources) |s| allocator.free(s);
        allocator.free(self.sources);
    }
};

/// Build batch transaction bytes
pub fn buildBatchTransactionTxBytes(
    client: *SuiRpcClient,
    sender: []const u8,
    items: []const BatchItem,
    gas_budget: ?u64,
    gas_price: ?u64,
) ![]u8 {
    // Build transactions array
    var transactions = std.json.Array.init(client.allocator);
    defer transactions.deinit();

    for (items) |item| {
        var tx_obj = std.json.ObjectMap.init(client.allocator);
        
        switch (item) {
            .move_call => |mc| {
                try tx_obj.put("kind", .{ .string = "moveCall" });
                try tx_obj.put("package", .{ .string = mc.package });
                try tx_obj.put("module", .{ .string = mc.module });
                try tx_obj.put("function", .{ .string = mc.function });
            },
            .transfer => |tr| {
                try tx_obj.put("kind", .{ .string = "transferObjects" });
                var obj_ids = std.json.Array.init(client.allocator);
                for (tr.object_ids) |id| {
                    try obj_ids.append(.{ .string = id });
                }
                try tx_obj.put("objectIds", .{ .array = obj_ids });
                try tx_obj.put("recipient", .{ .string = tr.recipient });
            },
            .split_coins => |sc| {
                try tx_obj.put("kind", .{ .string = "splitCoins" });
                try tx_obj.put("coinObjectId", .{ .string = sc.coin_object_id });
                var amounts = std.json.Array.init(client.allocator);
                for (sc.amounts) |amt| {
                    try amounts.append(.{ .integer = @intCast(amt) });
                }
                try tx_obj.put("amounts", .{ .array = amounts });
            },
            .merge_coins => |mc| {
                try tx_obj.put("kind", .{ .string = "mergeCoins" });
                try tx_obj.put("destination", .{ .string = mc.destination });
                var sources = std.json.Array.init(client.allocator);
                for (mc.sources) |src| {
                    try sources.append(.{ .string = src });
                }
                try tx_obj.put("sources", .{ .array = sources });
            },
        }
        
        try transactions.append(.{ .object = tx_obj });
    }

    // Build full transaction data
    var tx_data = std.json.ObjectMap.init(client.allocator);
    defer tx_data.deinit();

    try tx_data.put("sender", .{ .string = sender });
    try tx_data.put("transactions", .{ .array = transactions });
    
    if (gas_budget) |budget| {
        const budget_str = try std.fmt.allocPrint(client.allocator, "{d}", .{budget});
        defer client.allocator.free(budget_str);
        try tx_data.put("gasBudget", .{ .string = budget_str });
    }

    if (gas_price) |price| {
        const price_str = try std.fmt.allocPrint(client.allocator, "{d}", .{price});
        defer client.allocator.free(price_str);
        try tx_data.put("gasPrice", .{ .string = price_str });
    }

    // Serialize and call RPC
    const json_str = try std.json.stringifyAlloc(client.allocator, .{ .object = tx_data }, .{});
    defer client.allocator.free(json_str);

    const params_json = try std.fmt.allocPrint(client.allocator, "[{s}]", .{json_str});
    defer client.allocator.free(params_json);

    const response = try client.call("unsafe_batchTransaction", params_json);
    return response;
}

// ============================================================
// Tests
// ============================================================

test "MoveCallParams lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var params = MoveCallParams{
        .package = try allocator.dupe(u8, "0x2"),
        .module = try allocator.dupe(u8, "sui"),
        .function = try allocator.dupe(u8, "transfer"),
        .type_arguments = try allocator.alloc([]const u8, 1),
        .arguments = try allocator.alloc([]const u8, 1),
    };
    params.type_arguments[0] = try allocator.dupe(u8, "0x2::sui::SUI");
    params.arguments[0] = try allocator.dupe(u8, "arg1");
    defer params.deinit(allocator);

    try testing.expectEqualStrings("0x2", params.package);
}

test "TransferParams lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var params = TransferParams{
        .object_ids = try allocator.alloc([]const u8, 1),
        .recipient = try allocator.dupe(u8, "0x123"),
    };
    params.object_ids[0] = try allocator.dupe(u8, "0xobj1");
    defer params.deinit(allocator);

    try testing.expectEqualStrings("0x123", params.recipient);
}

test "SplitCoinsParams lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var params = SplitCoinsParams{
        .coin_object_id = try allocator.dupe(u8, "0xcoin"),
        .amounts = try allocator.alloc(u64, 2),
    };
    params.amounts[0] = 100;
    params.amounts[1] = 200;
    defer params.deinit(allocator);

    try testing.expectEqual(@as(u64, 100), params.amounts[0]);
}

test "MergeCoinsParams lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var params = MergeCoinsParams{
        .destination = try allocator.dupe(u8, "0xdest"),
        .sources = try allocator.alloc([]const u8, 2),
    };
    params.sources[0] = try allocator.dupe(u8, "0xsrc1");
    params.sources[1] = try allocator.dupe(u8, "0xsrc2");
    defer params.deinit(allocator);

    try testing.expectEqualStrings("0xdest", params.destination);
}

test "BatchItem union" {
    const testing = std.testing;
    
    const item = BatchItem{ .move_call = .{
        .package = "0x2",
        .module = "sui",
        .function = "transfer",
    }};
    
    try testing.expect(item == .move_call);
}
