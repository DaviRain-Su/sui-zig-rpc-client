/// tx_request_builder/types.zig - Core types for transaction request builder
const std = @import("std");

/// Command result aliases for tracking result references
pub const CommandResultAliases = std.StringHashMapUnmanaged(u16);

/// Nested result specification for accessing nested command outputs
pub const NestedResultSpec = struct {
    command_index: u16,
    result_index: u16,
};

/// Programmatic request options
pub const ProgrammaticRequestOptions = struct {
    /// Request alias for result references
    alias: ?[]const u8 = null,
    /// Gas budget for the transaction
    gas_budget: ?u64 = null,
    /// Gas price for the transaction
    gas_price: ?u64 = null,
    /// Sender address override
    sender: ?[]const u8 = null,
    /// Whether to execute immediately
    execute: bool = false,
    /// Whether to simulate before execution
    simulate: bool = true,

    pub fn deinit(self: *ProgrammaticRequestOptions, allocator: std.mem.Allocator) void {
        if (self.alias) |a| allocator.free(a);
        if (self.sender) |s| allocator.free(s);
    }
};

/// Command request configuration
pub const CommandRequestConfig = struct {
    /// Command type (move_call, transfer, etc.)
    command_type: []const u8,
    /// Command-specific parameters
    parameters: std.json.Value,
    /// Expected return type
    return_type: ?[]const u8 = null,
    /// Whether this command produces a result
    produces_result: bool = true,

    pub fn deinit(self: *CommandRequestConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.command_type);
        self.parameters.deinit(allocator);
        if (self.return_type) |rt| allocator.free(rt);
    }
};

/// Programmatic artifact kind
pub const ProgrammaticArtifactKind = enum {
    transaction_block,
    move_call,
    transfer,
    split_coins,
    merge_coins,
    publish,
    upgrade,
    make_move_vec,
    pure,
};

/// Account session kind
pub const AccountSessionKind = enum {
    none,
    sign_personal_message,
    passkey,
    zklogin,
};

/// Resolved command value with optional ownership
pub const ResolvedCommandValue = struct {
    value: []const u8,
    owned: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedCommandValue, allocator: std.mem.Allocator) void {
        if (self.owned) |value| allocator.free(value);
    }
};

/// Collection of resolved command values
pub const ResolvedCommandValues = struct {
    items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_items: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ResolvedCommandValues, allocator: std.mem.Allocator) void {
        for (self.owned_items.items) |value| allocator.free(value);
        self.items.deinit(allocator);
        self.owned_items.deinit(allocator);
    }
};

/// Future wallet account for session-based signing
pub const FutureWalletAccount = struct {
    /// Wallet identifier
    id: []const u8,
    /// Wallet type
    wallet_type: []const u8,
    /// Expected address (optional)
    expected_address: ?[]const u8 = null,
    /// Session challenge for authorization
    session_challenge: ?[]const u8 = null,

    pub fn deinit(self: *FutureWalletAccount, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.wallet_type);
        if (self.expected_address) |a| allocator.free(a);
        if (self.session_challenge) |c| allocator.free(c);
    }
};

// ============================================================
// Tests
// ============================================================

test "ProgrammaticRequestOptions lifecycle" {
    const testing = std.testing;

    var opts = ProgrammaticRequestOptions{
        .alias = try testing.allocator.dupe(u8, "test_alias"),
        .gas_budget = 1000000,
        .execute = true,
    };
    defer opts.deinit(testing.allocator);

    try testing.expectEqualStrings("test_alias", opts.alias.?);
    try testing.expectEqual(@as(?u64, 1000000), opts.gas_budget);
    try testing.expect(opts.execute);
}

test "ResolvedCommandValue lifecycle" {
    const testing = std.testing;

    var resolved = ResolvedCommandValue{
        .value = "test_value",
        .owned = try testing.allocator.dupe(u8, "owned_value"),
    };
    defer resolved.deinit(testing.allocator);

    try testing.expectEqualStrings("test_value", resolved.value);
    try testing.expectEqualStrings("owned_value", resolved.owned.?);
}

test "ResolvedCommandValues lifecycle" {
    const testing = std.testing;

    var values = ResolvedCommandValues{};
    defer values.deinit(testing.allocator);

    try values.items.append(testing.allocator, "item1");
    const owned = try testing.allocator.dupe(u8, "owned_item");
    try values.owned_items.append(testing.allocator, owned);

    try testing.expectEqual(@as(usize, 1), values.items.items.len);
    try testing.expectEqual(@as(usize, 1), values.owned_items.items.len);
}

test "FutureWalletAccount lifecycle" {
    const testing = std.testing;

    var account = FutureWalletAccount{
        .id = try testing.allocator.dupe(u8, "wallet_id"),
        .wallet_type = try testing.allocator.dupe(u8, "passkey"),
        .expected_address = try testing.allocator.dupe(u8, "0x123"),
    };
    defer account.deinit(testing.allocator);

    try testing.expectEqualStrings("wallet_id", account.id);
    try testing.expectEqualStrings("passkey", account.wallet_type);
}

test "ProgrammaticArtifactKind enum" {
    const testing = std.testing;

    const kind = ProgrammaticArtifactKind.transaction_block;
    try testing.expectEqual(ProgrammaticArtifactKind.transaction_block, kind);
}

test "AccountSessionKind enum" {
    const testing = std.testing;

    const kind = AccountSessionKind.sign_personal_message;
    try testing.expectEqual(AccountSessionKind.sign_personal_message, kind);
}

test "NestedResultSpec structure" {
    const testing = std.testing;

    const spec = NestedResultSpec{
        .command_index = 5,
        .result_index = 2,
    };

    try testing.expectEqual(@as(u16, 5), spec.command_index);
    try testing.expectEqual(@as(u16, 2), spec.result_index);
}

test "CommandRequestConfig lifecycle" {
    const testing = std.testing;

    var config = CommandRequestConfig{
        .command_type = try testing.allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = .{} },
        .produces_result = true,
    };
    defer config.deinit(testing.allocator);

    try testing.expectEqualStrings("move_call", config.command_type);
}
