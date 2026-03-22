/// commands/adapter.zig - Adapter to bridge old and new RPC client APIs
const std = @import("std");
const client = @import("sui_client_zig");

// Use new RPC client from sui_client_zig module
const SuiRpcClient = client.rpc_client_new.SuiRpcClient;
const ClientError = client.rpc_client_new.ClientError;

/// Adapter for RpcRequest - maps old to new
pub const RpcRequest = struct {
    method: []const u8,
    params: []const u8,

    pub fn toJson(self: RpcRequest, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{{\"method\":\"{s}\",\"params\":{s}}}", .{
            self.method,
            self.params,
        });
    }
};

/// Adapter for ReadQueryActionResult
pub const ReadQueryActionResult = union(enum) {
    balance: BalanceResult,
    object: ObjectResult,
    objects: []ObjectResult,
    transaction: TransactionResult,
    events: []EventResult,
    errors: []const u8,

    pub fn deinit(self: *ReadQueryActionResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .errors => |e| allocator.free(e),
            .objects => |objs| {
                for (objs) |*obj| obj.deinit(allocator);
                allocator.free(objs);
            },
            .events => |events| {
                for (events) |*evt| evt.deinit(allocator);
                allocator.free(events);
            },
            else => {},
        }
    }
};

pub const BalanceResult = struct {
    coin_type: []const u8,
    total_balance: u64,
    coin_object_count: u32,
};

pub const ObjectResult = struct {
    object_id: []const u8,
    version: u64,
    digest: []const u8,
    type: ?[]const u8,
    content: ?[]const u8,

    pub fn deinit(self: *ObjectResult, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
        if (self.type) |t| allocator.free(t);
        if (self.content) |c| allocator.free(c);
    }
};

pub const TransactionResult = struct {
    digest: []const u8,
    status: []const u8,

    pub fn deinit(self: *TransactionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.digest);
        allocator.free(self.status);
    }
};

pub const EventResult = struct {
    event_type: []const u8,
    package_id: []const u8,
    sender: []const u8,

    pub fn deinit(self: *EventResult, allocator: std.mem.Allocator) void {
        allocator.free(self.event_type);
        allocator.free(self.package_id);
        allocator.free(self.sender);
    }
};

/// Adapter for ProgrammaticClientAction
pub const ProgrammaticClientAction = union(enum) {
    /// Build a transaction
    build_transaction: BuildTransactionAction,
    /// Simulate a transaction
    simulate_transaction: SimulateTransactionAction,
    /// Execute a transaction
    execute_transaction: ExecuteTransactionAction,
    /// Query balance
    query_balance: QueryBalanceAction,
    /// Query object
    query_object: QueryObjectAction,
    /// Query objects owned by address
    query_owned_objects: QueryOwnedObjectsAction,
    /// Query events
    query_events: QueryEventsAction,

    pub fn deinit(self: *ProgrammaticClientAction, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .build_transaction => |*a| a.deinit(allocator),
            .simulate_transaction => |*a| a.deinit(allocator),
            .execute_transaction => |*a| a.deinit(allocator),
            .query_balance => |*a| a.deinit(allocator),
            .query_object => |*a| a.deinit(allocator),
            .query_owned_objects => |*a| a.deinit(allocator),
            .query_events => |*a| a.deinit(allocator),
        }
    }
};

pub const BuildTransactionAction = struct {
    sender: []const u8,
    commands_json: []const u8,
    gas_budget: ?u64,

    pub fn deinit(self: *BuildTransactionAction, allocator: std.mem.Allocator) void {
        allocator.free(self.sender);
        allocator.free(self.commands_json);
    }
};

pub const SimulateTransactionAction = struct {
    tx_bytes: []const u8,

    pub fn deinit(self: *SimulateTransactionAction, allocator: std.mem.Allocator) void {
        allocator.free(self.tx_bytes);
    }
};

pub const ExecuteTransactionAction = struct {
    tx_bytes: []const u8,
    signatures: [][]const u8,

    pub fn deinit(self: *ExecuteTransactionAction, allocator: std.mem.Allocator) void {
        allocator.free(self.tx_bytes);
        for (self.signatures) |sig| allocator.free(sig);
        allocator.free(self.signatures);
    }
};

pub const QueryBalanceAction = struct {
    address: []const u8,
    coin_type: ?[]const u8,

    pub fn deinit(self: *QueryBalanceAction, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
        if (self.coin_type) |ct| allocator.free(ct);
    }
};

pub const QueryObjectAction = struct {
    object_id: []const u8,
    options: ObjectDataOptions,

    pub fn deinit(self: *QueryObjectAction, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
    }
};

pub const QueryOwnedObjectsAction = struct {
    address: []const u8,
    filter: ?OwnedObjectsFilter,
    options: ObjectDataOptions,

    pub fn deinit(self: *QueryOwnedObjectsAction, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
    }
};

pub const QueryEventsAction = struct {
    filter: EventFilter,
    cursor: ?[]const u8,
    limit: ?u32,

    pub fn deinit(self: *QueryEventsAction, allocator: std.mem.Allocator) void {
        if (self.cursor) |c| allocator.free(c);
    }
};

/// Adapter for ProgrammaticClientActionResult
pub const ProgrammaticClientActionResult = union(enum) {
    build_transaction: BuildTransactionResult,
    simulate_transaction: SimulateTransactionResult,
    execute_transaction: ExecuteTransactionResult,
    query: ReadQueryActionResult,
    errors: []const u8,

    pub fn deinit(self: *ProgrammaticClientActionResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .build_transaction => |*r| r.deinit(allocator),
            .simulate_transaction => |*r| r.deinit(allocator),
            .execute_transaction => |*r| r.deinit(allocator),
            .query => |*r| r.deinit(allocator),
            .errors => |e| allocator.free(e),
        }
    }
};

pub const BuildTransactionResult = struct {
    tx_bytes: []const u8,

    pub fn deinit(self: *BuildTransactionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.tx_bytes);
    }
};

pub const SimulateTransactionResult = struct {
    effects: TransactionEffects,
    events: []EventResult,

    pub fn deinit(self: *SimulateTransactionResult, allocator: std.mem.Allocator) void {
        for (self.events) |*evt| evt.deinit(allocator);
        allocator.free(self.events);
    }
};

pub const ExecuteTransactionResult = struct {
    digest: []const u8,
    effects: TransactionEffects,
    events: []EventResult,

    pub fn deinit(self: *ExecuteTransactionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.digest);
        for (self.events) |*evt| evt.deinit(allocator);
        allocator.free(self.events);
    }
};

pub const TransactionEffects = struct {
    status: TransactionStatus,
    gas_used: GasCost,
    created: []ObjectResult,
    mutated: []ObjectResult,
    deleted: [][]const u8,

    pub fn deinit(self: *TransactionEffects, allocator: std.mem.Allocator) void {
        for (self.created) |*obj| obj.deinit(allocator);
        allocator.free(self.created);
        for (self.mutated) |*obj| obj.deinit(allocator);
        allocator.free(self.mutated);
        for (self.deleted) |d| allocator.free(d);
        allocator.free(self.deleted);
    }
};

pub const TransactionStatus = enum {
    success,
    failure,
};

pub const GasCost = struct {
    computation_cost: u64,
    storage_cost: u64,
    storage_rebate: u64,
};

/// Adapter for ProgrammaticClientActionOrChallengePromptResult
pub const ProgrammaticClientActionOrChallengePromptResult = union(enum) {
    result: ProgrammaticClientActionResult,
    challenge: ChallengePrompt,
};

pub const ChallengePrompt = struct {
    challenge_type: []const u8,
    challenge_data: []const u8,
    expected_signer: []const u8,

    pub fn deinit(self: *ChallengePrompt, allocator: std.mem.Allocator) void {
        allocator.free(self.challenge_type);
        allocator.free(self.challenge_data);
        allocator.free(self.expected_signer);
    }
};

/// Adapter for ObjectDataOptions
pub const ObjectDataOptions = struct {
    show_type: bool = false,
    show_content: bool = false,
    show_owner: bool = false,
    show_previous_transaction: bool = false,
    show_storage_rebate: bool = false,
    show_display: bool = false,

    pub fn toJson(self: ObjectDataOptions) []const u8 {
        // Return static JSON for common combinations
        if (self.show_type and self.show_content) {
            return "{\"showType\":true,\"showContent\":true}";
        } else if (self.show_type) {
            return "{\"showType\":true}";
        } else if (self.show_content) {
            return "{\"showContent\":true}";
        }
        return "{}";
    }
};

/// Adapter for DynamicFieldName
pub const DynamicFieldName = struct {
    type: []const u8,
    value: []const u8,

    pub fn deinit(self: *DynamicFieldName, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.value);
    }
};

/// Adapter for DynamicFieldPageRequest
pub const DynamicFieldPageRequest = struct {
    cursor: ?[]const u8,
    limit: ?u32,

    pub fn deinit(self: *DynamicFieldPageRequest, allocator: std.mem.Allocator) void {
        if (self.cursor) |c| allocator.free(c);
    }
};

/// Adapter for ObjectReadOptions
pub const ObjectReadOptions = struct {
    show_type: bool = false,
    show_content: bool = false,
    show_owner: bool = false,
    show_previous_transaction: bool = false,
    show_storage_rebate: bool = false,
    show_display: bool = false,

    pub fn toJson(self: ObjectReadOptions) []const u8 {
        const opts = ObjectDataOptions{
            .show_type = self.show_type,
            .show_content = self.show_content,
            .show_owner = self.show_owner,
            .show_previous_transaction = self.show_previous_transaction,
            .show_storage_rebate = self.show_storage_rebate,
            .show_display = self.show_display,
        };
        return opts.toJson();
    }
};

/// Adapter for OwnedObjectsFilter
pub const OwnedObjectsFilter = struct {
    object_type: ?[]const u8,

    pub fn deinit(self: *OwnedObjectsFilter, allocator: std.mem.Allocator) void {
        if (self.object_type) |ot| allocator.free(ot);
    }
};

/// Adapter for EventFilter
pub const EventFilter = struct {
    sender: ?[]const u8,
    event_type: ?[]const u8,
    package: ?[]const u8,
    module: ?[]const u8,

    pub fn deinit(self: *EventFilter, allocator: std.mem.Allocator) void {
        if (self.sender) |s| allocator.free(s);
        if (self.event_type) |et| allocator.free(et);
        if (self.package) |p| allocator.free(p);
        if (self.module) |m| allocator.free(m);
    }
};

/// Execute a programmatic action using the new API
pub fn executeAction(
    rpc_client: *SuiRpcClient,
    action: ProgrammaticClientAction,
    allocator: std.mem.Allocator,
) !ProgrammaticClientActionResult {
    _ = rpc_client;
    _ = action;
    // TODO: Implement using new RPC client
    return .{ .errors = try allocator.dupe(u8, "Not implemented") };
}

/// Execute or get challenge prompt
pub fn executeOrChallenge(
    rpc_client: *SuiRpcClient,
    action: ProgrammaticClientAction,
    allocator: std.mem.Allocator,
) !ProgrammaticClientActionOrChallengePromptResult {
    _ = rpc_client;
    _ = action;
    // TODO: Implement using new RPC client
    return .{ .result = .{ .errors = try allocator.dupe(u8, "Not implemented") } };
}

// ============================================================
// Tests
// ============================================================

test "RpcRequest toJson" {
    const testing = std.testing;
    const request = RpcRequest{
        .method = "sui_getBalance",
        .params = "[\"0x123\"]",
    };

    const json = try request.toJson(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "sui_getBalance"));
}

test "ObjectDataOptions toJson" {
    const testing = std.testing;
    const options = ObjectDataOptions{
        .show_type = true,
        .show_content = true,
    };

    const json = options.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "showType"));
}

test "ProgrammaticClientAction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var action = ProgrammaticClientAction{
        .query_balance = .{
            .address = try allocator.dupe(u8, "0x123"),
            .coin_type = try allocator.dupe(u8, "0x2::sui::SUI"),
        },
    };
    defer action.deinit(allocator);

    try testing.expectEqualStrings("0x123", action.query_balance.address);
}

test "ReadQueryActionResult deinit" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var result = ReadQueryActionResult{
        .balance = .{
            .coin_type = "0x2::sui::SUI",
            .total_balance = 1000,
            .coin_object_count = 1,
        },
    };
    defer result.deinit(allocator);

    try testing.expectEqual(@as(u64, 1000), result.balance.total_balance);
}
