const std = @import("std");

pub const ExecutionStatus = enum {
    unknown,
    success,
    failure,
};

pub const GasSummary = struct {
    computation_cost: ?u64 = null,
    storage_cost: ?u64 = null,
    storage_rebate: ?u64 = null,
    non_refundable_storage_fee: ?u64 = null,

    pub fn netGasSpent(self: GasSummary) ?i128 {
        const computation_cost = self.computation_cost orelse return null;
        const storage_cost = self.storage_cost orelse return null;
        const storage_rebate = self.storage_rebate orelse return null;
        return @as(i128, computation_cost) +
            @as(i128, storage_cost) +
            @as(i128, self.non_refundable_storage_fee orelse 0) -
            @as(i128, storage_rebate);
    }
};

pub const OwnedBalanceChange = struct {
    owner: ?[]u8 = null,
    coin_type: ?[]u8 = null,
    amount: ?i128 = null,

    pub fn deinit(self: *OwnedBalanceChange, allocator: std.mem.Allocator) void {
        if (self.owner) |value| allocator.free(value);
        if (self.coin_type) |value| allocator.free(value);
        self.* = .{};
    }
};

pub const OwnedExecutionInsights = struct {
    status: ExecutionStatus = .unknown,
    status_error: ?[]u8 = null,
    gas_summary: GasSummary = .{},
    balance_changes: []OwnedBalanceChange = &.{},

    pub fn deinit(self: *OwnedExecutionInsights, allocator: std.mem.Allocator) void {
        if (self.status_error) |value| allocator.free(value);
        for (self.balance_changes) |*change| change.deinit(allocator);
        if (self.balance_changes.len > 0) allocator.free(self.balance_changes);
        self.* = .{};
    }
};

fn duplicateStringField(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    field_name: []const u8,
) !?[]u8 {
    const value = obj.get(field_name) orelse return null;
    if (value != .string) return null;
    return try allocator.dupe(u8, value.string);
}

fn parseUnsignedValue(value: std.json.Value) !?u64 {
    return switch (value) {
        .integer => |integer| blk: {
            if (integer < 0) return error.InvalidCli;
            break :blk @as(u64, @intCast(integer));
        },
        .string => |string| try std.fmt.parseUnsigned(u64, string, 10),
        else => null,
    };
}

fn parseSignedValue(value: std.json.Value) !?i128 {
    return switch (value) {
        .integer => |integer| @as(i128, integer),
        .string => |string| try std.fmt.parseInt(i128, string, 10),
        else => null,
    };
}

fn extractOwnerString(
    allocator: std.mem.Allocator,
    owner_value: std.json.Value,
) !?[]u8 {
    return switch (owner_value) {
        .string => |string| try allocator.dupe(u8, string),
        .object => |object| blk: {
            if (object.get("AddressOwner")) |value| {
                if (value == .string) break :blk try allocator.dupe(u8, value.string);
            }
            if (object.get("ObjectOwner")) |value| {
                if (value == .string) break :blk try allocator.dupe(u8, value.string);
            }
            break :blk null;
        },
        else => null,
    };
}

fn parseBalanceChanges(
    allocator: std.mem.Allocator,
    root: std.json.Value,
) ![]OwnedBalanceChange {
    const balance_changes_value = switch (root) {
        .object => |object| object.get("balanceChanges") orelse return &.{},
        else => return &.{},
    };
    if (balance_changes_value != .array) return &.{};
    if (balance_changes_value.array.items.len == 0) return &.{};

    var items = try allocator.alloc(OwnedBalanceChange, balance_changes_value.array.items.len);
    errdefer allocator.free(items);
    for (items) |*item| item.* = .{};
    errdefer for (items) |*item| item.deinit(allocator);

    for (balance_changes_value.array.items, 0..) |entry, index| {
        if (entry != .object) continue;
        items[index].coin_type = try duplicateStringField(allocator, entry.object, "coinType");
        if (entry.object.get("amount")) |amount_value| {
            items[index].amount = try parseSignedValue(amount_value);
        }
        if (entry.object.get("owner")) |owner_value| {
            items[index].owner = try extractOwnerString(allocator, owner_value);
        }
    }
    return items;
}

fn responseContentRoot(root: std.json.Value) std.json.Value {
    if (root == .object) {
        if (root.object.get("result")) |result_value| {
            return result_value;
        }
    }
    return root;
}

pub fn extractExecutionInsights(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedExecutionInsights {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    var insights = OwnedExecutionInsights{};
    errdefer insights.deinit(allocator);
    const content = responseContentRoot(parsed.value);

    if (content == .object) {
        if (content.object.get("effects")) |effects_value| {
            if (effects_value == .object) {
                if (effects_value.object.get("status")) |status_value| {
                    if (status_value == .object) {
                        if (status_value.object.get("status")) |value| {
                            if (value == .string) {
                                if (std.mem.eql(u8, value.string, "success")) {
                                    insights.status = .success;
                                } else if (std.mem.eql(u8, value.string, "failure")) {
                                    insights.status = .failure;
                                }
                            }
                        }
                        insights.status_error = try duplicateStringField(allocator, status_value.object, "error");
                    }
                }

                if (effects_value.object.get("gasUsed")) |gas_used_value| {
                    if (gas_used_value == .object) {
                        if (gas_used_value.object.get("computationCost")) |value| {
                            insights.gas_summary.computation_cost = try parseUnsignedValue(value);
                        }
                        if (gas_used_value.object.get("storageCost")) |value| {
                            insights.gas_summary.storage_cost = try parseUnsignedValue(value);
                        }
                        if (gas_used_value.object.get("storageRebate")) |value| {
                            insights.gas_summary.storage_rebate = try parseUnsignedValue(value);
                        }
                        if (gas_used_value.object.get("nonRefundableStorageFee")) |value| {
                            insights.gas_summary.non_refundable_storage_fee = try parseUnsignedValue(value);
                        }
                    }
                }
            }
        }
    }

    insights.balance_changes = try parseBalanceChanges(allocator, content);
    return insights;
}

test "extractExecutionInsights parses D4-style success responses" {
    const testing = std.testing;

    const fixture =
        \\{
        \\  "digest": "5D4",
        \\  "effects": {
        \\    "status": { "status": "success" },
        \\    "gasUsed": {
        \\      "computationCost": "1000",
        \\      "storageCost": "200",
        \\      "storageRebate": "50",
        \\      "nonRefundableStorageFee": "1"
        \\    }
        \\  },
        \\  "balanceChanges": [
        \\    {
        \\      "owner": { "AddressOwner": "0xabc" },
        \\      "coinType": "0x2::sui::SUI",
        \\      "amount": "-1151"
        \\    },
        \\    {
        \\      "owner": { "AddressOwner": "0xdef" },
        \\      "coinType": "0x2::demo::COIN",
        \\      "amount": "7"
        \\    }
        \\  ]
        \\}
    ;

    var insights = try extractExecutionInsights(testing.allocator, fixture);
    defer insights.deinit(testing.allocator);

    try testing.expectEqual(ExecutionStatus.success, insights.status);
    try testing.expectEqual(@as(?u64, 1000), insights.gas_summary.computation_cost);
    try testing.expectEqual(@as(?u64, 200), insights.gas_summary.storage_cost);
    try testing.expectEqual(@as(?u64, 50), insights.gas_summary.storage_rebate);
    try testing.expectEqual(@as(?u64, 1), insights.gas_summary.non_refundable_storage_fee);
    try testing.expectEqual(@as(?i128, 1151), @abs(insights.gas_summary.netGasSpent().?));
    try testing.expectEqual(@as(usize, 2), insights.balance_changes.len);
    try testing.expectEqualStrings("0xabc", insights.balance_changes[0].owner.?);
    try testing.expectEqualStrings("0x2::sui::SUI", insights.balance_changes[0].coin_type.?);
    try testing.expectEqual(@as(?i128, -1151), insights.balance_changes[0].amount);
    try testing.expectEqualStrings("0xdef", insights.balance_changes[1].owner.?);
    try testing.expectEqual(@as(?i128, 7), insights.balance_changes[1].amount);
}

test "extractExecutionInsights parses failure status and missing optional fields" {
    const testing = std.testing;

    const fixture =
        \\{
        \\  "effects": {
        \\    "status": {
        \\      "status": "failure",
        \\      "error": "InsufficientGas"
        \\    },
        \\    "gasUsed": {
        \\      "computationCost": 10,
        \\      "storageCost": 2,
        \\      "storageRebate": 1
        \\    }
        \\  }
        \\}
    ;

    var insights = try extractExecutionInsights(testing.allocator, fixture);
    defer insights.deinit(testing.allocator);

    try testing.expectEqual(ExecutionStatus.failure, insights.status);
    try testing.expectEqualStrings("InsufficientGas", insights.status_error.?);
    try testing.expectEqual(@as(?u64, 10), insights.gas_summary.computation_cost);
    try testing.expectEqual(@as(?u64, 2), insights.gas_summary.storage_cost);
    try testing.expectEqual(@as(?u64, 1), insights.gas_summary.storage_rebate);
    try testing.expectEqual(@as(?u64, null), insights.gas_summary.non_refundable_storage_fee);
    try testing.expectEqual(@as(?i128, 11), insights.gas_summary.netGasSpent());
    try testing.expectEqual(@as(usize, 0), insights.balance_changes.len);
}

test "extractExecutionInsights tolerates non-address owners in balance changes" {
    const testing = std.testing;

    const fixture =
        \\{
        \\  "effects": { "status": { "status": "success" } },
        \\  "balanceChanges": [
        \\    {
        \\      "owner": { "Shared": { "initial_shared_version": 1 } },
        \\      "coinType": "0x2::demo::COIN",
        \\      "amount": "1"
        \\    }
        \\  ]
        \\}
    ;

    var insights = try extractExecutionInsights(testing.allocator, fixture);
    defer insights.deinit(testing.allocator);

    try testing.expectEqual(ExecutionStatus.success, insights.status);
    try testing.expectEqual(@as(usize, 1), insights.balance_changes.len);
    try testing.expectEqual(@as(?[]u8, null), insights.balance_changes[0].owner);
    try testing.expectEqualStrings("0x2::demo::COIN", insights.balance_changes[0].coin_type.?);
    try testing.expectEqual(@as(?i128, 1), insights.balance_changes[0].amount);
}

test "extractExecutionInsights parses rpc result envelopes" {
    const testing = std.testing;

    const fixture =
        \\{
        \\  "jsonrpc": "2.0",
        \\  "result": {
        \\    "effects": {
        \\      "status": { "status": "success" },
        \\      "gasUsed": {
        \\        "computationCost": "9",
        \\        "storageCost": "2",
        \\        "storageRebate": "1"
        \\      }
        \\    },
        \\    "balanceChanges": [
        \\      {
        \\        "owner": { "AddressOwner": "0xabc" },
        \\        "coinType": "0x2::sui::SUI",
        \\        "amount": "-10"
        \\      }
        \\    ]
        \\  }
        \\}
    ;

    var insights = try extractExecutionInsights(testing.allocator, fixture);
    defer insights.deinit(testing.allocator);

    try testing.expectEqual(ExecutionStatus.success, insights.status);
    try testing.expectEqual(@as(?u64, 9), insights.gas_summary.computation_cost);
    try testing.expectEqual(@as(?i128, 10), @abs(insights.balance_changes[0].amount.?));
}

test "extractExecutionInsights handles object owners integer amounts and missing gas fields" {
    const testing = std.testing;

    const fixture =
        \\{
        \\  "result": {
        \\    "effects": {
        \\      "status": { "status": "success" },
        \\      "gasUsed": {
        \\        "computationCost": 12
        \\      }
        \\    },
        \\    "balanceChanges": [
        \\      {
        \\        "owner": { "ObjectOwner": "0xowned-object" },
        \\        "coinType": "0x2::demo::COIN",
        \\        "amount": 9
        \\      },
        \\      {
        \\        "owner": { "AddressOwner": "0xabc" },
        \\        "coinType": "0x2::demo::COIN"
        \\      }
        \\    ]
        \\  }
        \\}
    ;

    var insights = try extractExecutionInsights(testing.allocator, fixture);
    defer insights.deinit(testing.allocator);

    try testing.expectEqual(ExecutionStatus.success, insights.status);
    try testing.expectEqual(@as(?u64, 12), insights.gas_summary.computation_cost);
    try testing.expectEqual(@as(?u64, null), insights.gas_summary.storage_cost);
    try testing.expectEqual(@as(?i128, null), insights.gas_summary.netGasSpent());
    try testing.expectEqual(@as(usize, 2), insights.balance_changes.len);
    try testing.expectEqualStrings("0xowned-object", insights.balance_changes[0].owner.?);
    try testing.expectEqual(@as(?i128, 9), insights.balance_changes[0].amount);
    try testing.expectEqualStrings("0xabc", insights.balance_changes[1].owner.?);
    try testing.expectEqual(@as(?i128, null), insights.balance_changes[1].amount);
}

test "extractExecutionInsights keeps failure responses with balance changes" {
    const testing = std.testing;

    const fixture =
        \\{
        \\  "result": {
        \\    "effects": {
        \\      "status": {
        \\        "status": "failure",
        \\        "error": "MoveAbort"
        \\      },
        \\      "gasUsed": {
        \\        "computationCost": "20",
        \\        "storageCost": "3",
        \\        "storageRebate": "1"
        \\      }
        \\    },
        \\    "balanceChanges": [
        \\      {
        \\        "owner": { "AddressOwner": "0xfail" },
        \\        "coinType": "0x2::sui::SUI",
        \\        "amount": "-22"
        \\      }
        \\    ]
        \\  }
        \\}
    ;

    var insights = try extractExecutionInsights(testing.allocator, fixture);
    defer insights.deinit(testing.allocator);

    try testing.expectEqual(ExecutionStatus.failure, insights.status);
    try testing.expectEqualStrings("MoveAbort", insights.status_error.?);
    try testing.expectEqual(@as(?i128, 22), @abs(insights.gas_summary.netGasSpent().?));
    try testing.expectEqual(@as(usize, 1), insights.balance_changes.len);
    try testing.expectEqualStrings("0xfail", insights.balance_changes[0].owner.?);
    try testing.expectEqual(@as(?i128, -22), insights.balance_changes[0].amount);
}
