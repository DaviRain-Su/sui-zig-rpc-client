/// client/rpc_client/transaction.zig - Transaction methods for RPC client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Transaction simulation result
pub const SimulationResult = struct {
    effects: TransactionEffects,
    events: []Event,
    object_changes: []ObjectChange,
    balance_changes: []BalanceChange,

    pub fn deinit(self: *SimulationResult, allocator: std.mem.Allocator) void {
        self.effects.deinit(allocator);
        for (self.events) |*event| event.deinit(allocator);
        allocator.free(self.events);
        for (self.object_changes) |*change| change.deinit(allocator);
        allocator.free(self.object_changes);
        for (self.balance_changes) |*change| change.deinit(allocator);
        allocator.free(self.balance_changes);
    }
};

/// Transaction effects
pub const TransactionEffects = struct {
    status: TransactionStatus,
    gas_used: GasCostSummary,
    modified_at_versions: []ModifiedAtVersion,
    shared_objects: []SharedObjectRef,
    transaction_digest: []const u8,
    created: []ObjectRef,
    mutated: []ObjectRef,
    unwrapped: []ObjectRef,
    deleted: []ObjectRef,
    wrapped: []ObjectRef,
    gas_object: ObjectRef,
    events_digest: ?[]const u8,
    dependencies: [][]const u8,

    pub fn deinit(self: *TransactionEffects, allocator: std.mem.Allocator) void {
        allocator.free(self.transaction_digest);
        for (self.modified_at_versions) |*v| v.deinit(allocator);
        allocator.free(self.modified_at_versions);
        for (self.shared_objects) |*o| o.deinit(allocator);
        allocator.free(self.shared_objects);
        for (self.created) |*o| o.deinit(allocator);
        allocator.free(self.created);
        for (self.mutated) |*o| o.deinit(allocator);
        allocator.free(self.mutated);
        for (self.unwrapped) |*o| o.deinit(allocator);
        allocator.free(self.unwrapped);
        for (self.deleted) |*o| o.deinit(allocator);
        allocator.free(self.deleted);
        for (self.wrapped) |*o| o.deinit(allocator);
        allocator.free(self.wrapped);
        self.gas_object.deinit(allocator);
        if (self.events_digest) |d| allocator.free(d);
        for (self.dependencies) |d| allocator.free(d);
        allocator.free(self.dependencies);
    }
};

/// Transaction status
pub const TransactionStatus = enum {
    success,
    failure,

    pub fn fromString(status: []const u8) TransactionStatus {
        if (std.mem.eql(u8, status, "success")) return .success;
        return .failure;
    }
};

/// Gas cost summary
pub const GasCostSummary = struct {
    computation_cost: u64,
    storage_cost: u64,
    storage_rebate: u64,
    non_refundable_storage_fee: u64,

    pub fn netCost(self: GasCostSummary) i64 {
        return @as(i64, @intCast(self.computation_cost + self.storage_cost)) -
            @as(i64, @intCast(self.storage_rebate));
    }
};

/// Modified at version
pub const ModifiedAtVersion = struct {
    object_id: []const u8,
    sequence_number: u64,

    pub fn deinit(self: *ModifiedAtVersion, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
    }
};

/// Shared object reference
pub const SharedObjectRef = struct {
    object_id: []const u8,
    initial_shared_version: u64,
    mutable: bool,

    pub fn deinit(self: *SharedObjectRef, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
    }
};

/// Object reference
pub const ObjectRef = struct {
    object_id: []const u8,
    version: u64,
    digest: []const u8,

    pub fn deinit(self: *ObjectRef, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
    }
};

/// Event
pub const Event = struct {
    transaction_digest: []const u8,
    event_sequence: u64,
    event_type: []const u8,
    sender: []const u8,
    timestamp_ms: ?u64,
    parsed_json: ?[]const u8,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        allocator.free(self.transaction_digest);
        allocator.free(self.event_type);
        allocator.free(self.sender);
        if (self.parsed_json) |json| allocator.free(json);
    }
};

/// Object change
pub const ObjectChange = struct {
    type: ObjectChangeType,
    sender: []const u8,
    owner_type: []const u8,
    object_id: []const u8,
    object_type: []const u8,
    version: u64,
    digest: []const u8,

    pub fn deinit(self: *ObjectChange, allocator: std.mem.Allocator) void {
        allocator.free(self.sender);
        allocator.free(self.owner_type);
        allocator.free(self.object_id);
        allocator.free(self.object_type);
        allocator.free(self.digest);
    }
};

/// Object change type
pub const ObjectChangeType = enum {
    created,
    mutated,
    deleted,
    wrapped,
    unwrapped,
};

/// Balance change
pub const BalanceChange = struct {
    owner: []const u8,
    coin_type: []const u8,
    amount: i64,

    pub fn deinit(self: *BalanceChange, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.coin_type);
    }
};

/// Simulate transaction
pub fn simulateTransaction(
    client: *SuiRpcClient,
    tx_bytes: []const u8,
    options: ?SimulationOptions,
) !SimulationResult {
    const params = if (options) |opts|
        try std.fmt.allocPrint(
            client.allocator,
            "[\"{s}\",{s}]",
            .{ tx_bytes, opts.toJson() },
        )
    else
        try std.fmt.allocPrint(client.allocator, "[\"{s}\",{{}}]", .{tx_bytes});
    defer client.allocator.free(params);

    const response = try client.call("sui_dryRunTransactionBlock", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseSimulationResult(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Simulation options
pub const SimulationOptions = struct {
    show_events: bool = true,
    show_object_changes: bool = true,
    show_balance_changes: bool = true,

    pub fn toJson(self: SimulationOptions) []const u8 {
        var buf: [256]u8 = undefined;
        return std.fmt.bufPrint(
            &buf,
            "{{\"showEvents\":{},\"showObjectChanges\":{},\"showBalanceChanges\":{}}}",
            .{ self.show_events, self.show_object_changes, self.show_balance_changes },
        ) catch "{}";
    }
};

/// Execute transaction
pub const ExecutionResult = struct {
    digest: []const u8,
    transaction: TransactionData,
    effects: TransactionEffects,
    events: []Event,
    object_changes: []ObjectChange,
    balance_changes: []BalanceChange,
    timestamp_ms: ?u64,
    checkpoint: ?u64,
    confirmed_local_execution: bool,

    pub fn deinit(self: *ExecutionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.digest);
        self.transaction.deinit(allocator);
        self.effects.deinit(allocator);
        for (self.events) |*event| event.deinit(allocator);
        allocator.free(self.events);
        for (self.object_changes) |*change| change.deinit(allocator);
        allocator.free(self.object_changes);
        for (self.balance_changes) |*change| change.deinit(allocator);
        allocator.free(self.balance_changes);
    }
};

/// Transaction data
pub const TransactionData = struct {
    sender: []const u8,
    gas_payment: ObjectRef,
    gas_price: u64,
    gas_budget: u64,

    pub fn deinit(self: *TransactionData, allocator: std.mem.Allocator) void {
        allocator.free(self.sender);
        self.gas_payment.deinit(allocator);
    }
};

/// Execute transaction
pub fn executeTransaction(
    client: *SuiRpcClient,
    tx_bytes: []const u8,
    signatures: [][]const u8,
    options: ?ExecutionOptions,
) !ExecutionResult {
    var signatures_json = std.ArrayList(u8).init(client.allocator);
    defer signatures_json.deinit();

    try signatures_json.append('[');
    for (signatures, 0..) |sig, i| {
        if (i > 0) try signatures_json.append(',');
        try std.fmt.format(signatures_json.writer(), "\"{s}\"", .{sig});
    }
    try signatures_json.append(']');

    const opts_json = if (options) |opts| opts.toJson() else "{}";

    const params = try std.fmt.allocPrint(
        client.allocator,
        "[\"{s}\",{s},{s}]",
        .{ tx_bytes, signatures_json.items, opts_json },
    );
    defer client.allocator.free(params);

    const response = try client.call("sui_executeTransactionBlock", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseExecutionResult(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Execution options
pub const ExecutionOptions = struct {
    show_events: bool = true,
    show_object_changes: bool = true,
    show_balance_changes: bool = true,
    show_input: bool = false,
    show_raw_input: bool = false,
    show_effects: bool = true,

    pub fn toJson(self: ExecutionOptions) []const u8 {
        var buf: [512]u8 = undefined;
        return std.fmt.bufPrint(
            &buf,
            "{{\"showEvents\":{},\"showObjectChanges\":{},\"showBalanceChanges\":{},\"showInput\":{},\"showRawInput\":{},\"showEffects\":{}}}",
            .{
                self.show_events,
                self.show_object_changes,
                self.show_balance_changes,
                self.show_input,
                self.show_raw_input,
                self.show_effects,
            },
        ) catch "{}";
    }
};

/// Parse simulation result from JSON
fn parseSimulationResult(allocator: std.mem.Allocator, value: std.json.Value) !SimulationResult {
    const effects = try parseTransactionEffects(allocator, value.object.get("effects").?);

    var events = std.ArrayList(Event).init(allocator);
    errdefer events.deinit();

    if (value.object.get("events")) |events_value| {
        if (events_value == .array) {
            for (events_value.array.items) |event_value| {
                const event = try parseEvent(allocator, event_value);
                try events.append(event);
            }
        }
    }

    var object_changes = std.ArrayList(ObjectChange).init(allocator);
    errdefer object_changes.deinit();

    if (value.object.get("objectChanges")) |changes_value| {
        if (changes_value == .array) {
            for (changes_value.array.items) |change_value| {
                const change = try parseObjectChange(allocator, change_value);
                try object_changes.append(change);
            }
        }
    }

    var balance_changes = std.ArrayList(BalanceChange).init(allocator);
    errdefer balance_changes.deinit();

    if (value.object.get("balanceChanges")) |changes_value| {
        if (changes_value == .array) {
            for (changes_value.array.items) |change_value| {
                const change = try parseBalanceChange(allocator, change_value);
                try balance_changes.append(change);
            }
        }
    }

    return SimulationResult{
        .effects = effects,
        .events = try events.toOwnedSlice(),
        .object_changes = try object_changes.toOwnedSlice(),
        .balance_changes = try balance_changes.toOwnedSlice(),
    };
}

/// Parse transaction effects from JSON
fn parseTransactionEffects(allocator: std.mem.Allocator, value: std.json.Value) !TransactionEffects {
    // Simplified parsing - full implementation would parse all fields
    const status = value.object.get("status").?;
    const status_str = status.object.get("status").?.string;

    const gas_used = value.object.get("gasUsed").?;

    return TransactionEffects{
        .status = TransactionStatus.fromString(status_str),
        .gas_used = GasCostSummary{
            .computation_cost = @intCast(gas_used.object.get("computationCost").?.integer),
            .storage_cost = @intCast(gas_used.object.get("storageCost").?.integer),
            .storage_rebate = @intCast(gas_used.object.get("storageRebate").?.integer),
            .non_refundable_storage_fee = @intCast(gas_used.object.get("nonRefundableStorageFee").?.integer),
        },
        .modified_at_versions = &.{},
        .shared_objects = &.{},
        .transaction_digest = try allocator.dupe(u8, value.object.get("transactionDigest").?.string),
        .created = &.{},
        .mutated = &.{},
        .unwrapped = &.{},
        .deleted = &.{},
        .wrapped = &.{},
        .gas_object = ObjectRef{
            .object_id = try allocator.dupe(u8, "0x0"),
            .version = 0,
            .digest = try allocator.dupe(u8, "0x0"),
        },
        .events_digest = null,
        .dependencies = &.{},
    };
}

/// Parse event from JSON
fn parseEvent(allocator: std.mem.Allocator, value: std.json.Value) !Event {
    return Event{
        .transaction_digest = try allocator.dupe(u8, value.object.get("transactionDigest").?.string),
        .event_sequence = @intCast(value.object.get("eventSequence").?.integer),
        .event_type = try allocator.dupe(u8, value.object.get("type").?.string),
        .sender = try allocator.dupe(u8, value.object.get("sender").?.string),
        .timestamp_ms = if (value.object.get("timestampMs")) |ts|
            if (ts == .integer) @intCast(ts.integer) else null
        else
            null,
        .parsed_json = null,
    };
}

/// Parse object change from JSON
fn parseObjectChange(allocator: std.mem.Allocator, value: std.json.Value) !ObjectChange {
    const change_type = value.object.get("type").?.string;

    return ObjectChange{
        .type = ObjectChangeType.fromString(change_type),
        .sender = try allocator.dupe(u8, value.object.get("sender").?.string),
        .owner_type = try allocator.dupe(u8, value.object.get("ownerType").?.string),
        .object_id = try allocator.dupe(u8, value.object.get("objectId").?.string),
        .object_type = try allocator.dupe(u8, value.object.get("objectType").?.string),
        .version = @intCast(value.object.get("version").?.integer),
        .digest = try allocator.dupe(u8, value.object.get("digest").?.string),
    };
}

/// Parse balance change from JSON
fn parseBalanceChange(allocator: std.mem.Allocator, value: std.json.Value) !BalanceChange {
    const amount_str = value.object.get("amount").?.string;
    const amount = try std.fmt.parseInt(i64, amount_str, 10);

    return BalanceChange{
        .owner = try allocator.dupe(u8, value.object.get("owner").?.string),
        .coin_type = try allocator.dupe(u8, value.object.get("coinType").?.string),
        .amount = amount,
    };
}

/// Parse execution result from JSON
fn parseExecutionResult(allocator: std.mem.Allocator, value: std.json.Value) !ExecutionResult {
    const digest = value.object.get("digest").?.string;
    const transaction = value.object.get("transaction").?;
    const effects = value.object.get("effects").?;

    return ExecutionResult{
        .digest = try allocator.dupe(u8, digest),
        .transaction = TransactionData{
            .sender = try allocator.dupe(u8, transaction.object.get("data").?.object.get("sender").?.string),
            .gas_payment = ObjectRef{
                .object_id = try allocator.dupe(u8, "0x0"),
                .version = 0,
                .digest = try allocator.dupe(u8, "0x0"),
            },
            .gas_price = 0,
            .gas_budget = 0,
        },
        .effects = try parseTransactionEffects(allocator, effects),
        .events = &.{},
        .object_changes = &.{},
        .balance_changes = &.{},
        .timestamp_ms = null,
        .checkpoint = null,
        .confirmed_local_execution = false,
    };
}

/// ObjectChangeType from string
fn ObjectChangeTypeFromString(str: []const u8) ObjectChangeType {
    if (std.mem.eql(u8, str, "created")) return .created;
    if (std.mem.eql(u8, str, "mutated")) return .mutated;
    if (std.mem.eql(u8, str, "deleted")) return .deleted;
    if (std.mem.eql(u8, str, "wrapped")) return .wrapped;
    return .unwrapped;
}

// ============================================================
// Tests
// ============================================================

test "GasCostSummary netCost" {
    const testing = std.testing;

    const gas = GasCostSummary{
        .computation_cost = 1000,
        .storage_cost = 500,
        .storage_rebate = 300,
        .non_refundable_storage_fee = 0,
    };

    try testing.expectEqual(@as(i64, 1200), gas.netCost());
}

test "TransactionStatus fromString" {
    const testing = std.testing;

    try testing.expectEqual(TransactionStatus.success, TransactionStatus.fromString("success"));
    try testing.expectEqual(TransactionStatus.failure, TransactionStatus.fromString("failure"));
    try testing.expectEqual(TransactionStatus.failure, TransactionStatus.fromString("other"));
}

test "SimulationOptions toJson" {
    const testing = std.testing;

    const opts = SimulationOptions{
        .show_events = true,
        .show_object_changes = false,
    };

    const json = opts.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "showEvents"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "true"));
}

test "ExecutionOptions toJson" {
    const testing = std.testing;

    const opts = ExecutionOptions{
        .show_events = true,
        .show_effects = true,
    };

    const json = opts.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "showEffects"));
}

test "ObjectRef structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var obj = ObjectRef{
        .object_id = try allocator.dupe(u8, "0x123"),
        .version = 1,
        .digest = try allocator.dupe(u8, "abc"),
    };
    defer obj.deinit(allocator);

    try testing.expectEqualStrings("0x123", obj.object_id);
}

test "Event structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event = Event{
        .transaction_digest = try allocator.dupe(u8, "0xabc"),
        .event_sequence = 0,
        .event_type = try allocator.dupe(u8, "0x2::event::Event"),
        .sender = try allocator.dupe(u8, "0x123"),
        .timestamp_ms = 1234567890,
        .parsed_json = null,
    };
    defer event.deinit(allocator);

    try testing.expectEqual(@as(u64, 0), event.event_sequence);
}

test "BalanceChange structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var change = BalanceChange{
        .owner = try allocator.dupe(u8, "0x123"),
        .coin_type = try allocator.dupe(u8, "0x2::sui::SUI"),
        .amount = -1000,
    };
    defer change.deinit(allocator);

    try testing.expectEqual(@as(i64, -1000), change.amount);
}
