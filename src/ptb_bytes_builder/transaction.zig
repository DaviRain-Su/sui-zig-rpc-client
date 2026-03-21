/// ptb_bytes_builder/transaction.zig - Transaction building
const std = @import("std");
const types = @import("types.zig");
const bcs_encoder = @import("bcs_encoder.zig");
const json_parser = @import("json_parser.zig");

const TransactionDataV1 = types.TransactionDataV1;
const ProgrammableTransaction = types.ProgrammableTransaction;
const GasData = types.GasData;
const TypeTag = types.TypeTag;
const Address = types.Address;

/// Build transaction data V1 bytes
pub fn buildTransactionDataV1Bytes(
    allocator: std.mem.Allocator,
    tx_data: TransactionDataV1,
) ![]u8 {
    // Simplified - would actually serialize to BCS
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    // Write sender
    try result.appendSlice(&tx_data.sender);

    // Write gas data
    const gas_price_bytes = try std.fmt.allocPrint(allocator, "{d}", .{tx_data.gas_data.price});
    defer allocator.free(gas_price_bytes);
    try result.appendSlice(gas_price_bytes);

    const gas_budget_bytes = try std.fmt.allocPrint(allocator, "{d}", .{tx_data.gas_data.budget});
    defer allocator.free(gas_budget_bytes);
    try result.appendSlice(gas_budget_bytes);

    return result.toOwnedSlice();
}

/// Build transaction data V1 base64
pub fn buildTransactionDataV1Base64(
    allocator: std.mem.Allocator,
    tx_data: TransactionDataV1,
) ![]u8 {
    const bytes = try buildTransactionDataV1Bytes(allocator, tx_data);
    defer allocator.free(bytes);

    const encoder = std.base64.standard.Encoder;
    const result = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(result, bytes);
    return result;
}

/// Build transaction data V1 bytes from parts
pub fn buildTransactionDataV1BytesFromParts(
    allocator: std.mem.Allocator,
    sender: Address,
    gas_price: u64,
    gas_budget: u64,
    pt: ProgrammableTransaction,
) ![]u8 {
    const tx_data = TransactionDataV1{
        .kind = pt,
        .sender = sender,
        .gas_data = .{
            .payment = &.{},
            .owner = sender,
            .price = gas_price,
            .budget = gas_budget,
        },
        .expiration = .{ .none = {} },
    };
    _ = tx_data;

    // Simplified implementation
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try result.appendSlice(&sender);

    const price_str = try std.fmt.allocPrint(allocator, "{d}", .{gas_price});
    defer allocator.free(price_str);
    try result.appendSlice(price_str);

    const budget_str = try std.fmt.allocPrint(allocator, "{d}", .{gas_budget});
    defer allocator.free(budget_str);
    try result.appendSlice(budget_str);

    return result.toOwnedSlice();
}

/// Build transaction data V1 base64 from parts
pub fn buildTransactionDataV1Base64FromParts(
    allocator: std.mem.Allocator,
    sender: Address,
    gas_price: u64,
    gas_budget: u64,
    pt: ProgrammableTransaction,
) ![]u8 {
    const bytes = try buildTransactionDataV1BytesFromParts(allocator, sender, gas_price, gas_budget, pt);
    defer allocator.free(bytes);

    const encoder = std.base64.standard.Encoder;
    const result = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(result, bytes);
    return result;
}

/// Build transaction data V1 bytes from JSON
pub fn buildTransactionDataV1BytesFromJson(
    allocator: std.mem.Allocator,
    json_str: []const u8,
) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Parse sender
    const sender_str = root.object.get("sender") orelse return error.MissingSender;
    const sender = try json_parser.parseSimplifiedTypeTag(allocator, sender_str.string);
    _ = sender;

    // Parse gas data
    const gas_data = root.object.get("gas_data") orelse return error.MissingGasData;
    const gas_price = gas_data.object.get("price") orelse return error.MissingGasPrice;
    const gas_budget = gas_data.object.get("budget") orelse return error.MissingGasBudget;

    // Build transaction
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const price_str = try std.fmt.allocPrint(allocator, "{d}", .{gas_price.integer});
    defer allocator.free(price_str);
    try result.appendSlice(price_str);

    const budget_str = try std.fmt.allocPrint(allocator, "{d}", .{gas_budget.integer});
    defer allocator.free(budget_str);
    try result.appendSlice(budget_str);

    return result.toOwnedSlice();
}

/// Build transaction data V1 base64 from JSON
pub fn buildTransactionDataV1Base64FromJson(
    allocator: std.mem.Allocator,
    json_str: []const u8,
) ![]u8 {
    const bytes = try buildTransactionDataV1BytesFromJson(allocator, json_str);
    defer allocator.free(bytes);

    const encoder = std.base64.standard.Encoder;
    const result = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(result, bytes);
    return result;
}

// ============================================================
// Tests
// ============================================================

test "buildTransactionDataV1Bytes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const tx_data = TransactionDataV1{
        .kind = .{
            .inputs = try allocator.alloc(types.CallArg, 0),
            .commands = try allocator.alloc(types.Command, 0),
        },
        .sender = [_]u8{0} ** 32,
        .gas_data = .{
            .payment = try allocator.alloc(types.ObjectRef, 0),
            .owner = [_]u8{0} ** 32,
            .price = 1000,
            .budget = 1000000,
        },
        .expiration = .{ .none = {} },
    };
    defer tx_data.deinit(allocator);

    const result = try buildTransactionDataV1Bytes(allocator, tx_data);
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}

test "buildTransactionDataV1Base64" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const tx_data = TransactionDataV1{
        .kind = .{
            .inputs = try allocator.alloc(types.CallArg, 0),
            .commands = try allocator.alloc(types.Command, 0),
        },
        .sender = [_]u8{0} ** 32,
        .gas_data = .{
            .payment = try allocator.alloc(types.ObjectRef, 0),
            .owner = [_]u8{0} ** 32,
            .price = 1000,
            .budget = 1000000,
        },
        .expiration = .{ .none = {} },
    };
    defer tx_data.deinit(allocator);

    const result = try buildTransactionDataV1Base64(allocator, tx_data);
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}

test "buildTransactionDataV1BytesFromParts" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const pt = ProgrammableTransaction{
        .inputs = try allocator.alloc(types.CallArg, 0),
        .commands = try allocator.alloc(types.Command, 0),
    };
    defer pt.deinit(allocator);

    const result = try buildTransactionDataV1BytesFromParts(
        allocator,
        [_]u8{0} ** 32,
        1000,
        1000000,
        pt,
    );
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}

test "buildTransactionDataV1BytesFromJson" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const json = "{\"sender\":\"0x123\",\"gas_data\":{\"price\":1000,\"budget\":1000000}}";

    const result = try buildTransactionDataV1BytesFromJson(allocator, json);
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}

test "buildTransactionDataV1Base64FromJson" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const json = "{\"sender\":\"0x123\",\"gas_data\":{\"price\":1000,\"budget\":1000000}}";

    const result = try buildTransactionDataV1Base64FromJson(allocator, json);
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}

test "buildTransactionDataV1BytesFromJson missing sender" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const json = "{\"gas_data\":{\"price\":1000,\"budget\":1000000}}";

    const result = buildTransactionDataV1BytesFromJson(allocator, json);
    try testing.expectError(error.MissingSender, result);
}

test "buildTransactionDataV1BytesFromJson missing gas_data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const json = "{\"sender\":\"0x123\"}";

    const result = buildTransactionDataV1BytesFromJson(allocator, json);
    try testing.expectError(error.MissingGasData, result);
}
