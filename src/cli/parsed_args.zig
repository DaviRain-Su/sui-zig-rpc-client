/// cli/parsed_args.zig - Parsed command line arguments
const std = @import("std");
const types = @import("types.zig");

/// Core parsed arguments structure (simplified version)
pub const ParsedArgs = struct {
    // Command info
    command: types.Command = .help,
    has_command: bool = false,
    show_usage: bool = false,

    // Global options
    pretty: bool = false,
    rpc_url: []const u8 = types.default_rpc_url,
    request_timeout_ms: ?u64 = null,
    confirm_timeout_ms: ?u64 = null,
    confirm_poll_ms: u64 = 2_000,

    // RPC method and params
    method: ?[]const u8 = null,
    params: ?[]const u8 = null,

    // Transaction options
    tx_bytes: ?[]const u8 = null,
    tx_options: ?[]const u8 = null,
    tx_digest: ?[]const u8 = null,
    tx_send_wait: bool = false,
    tx_send_summarize: bool = false,
    tx_send_observe: bool = false,

    // Transaction build options
    tx_build_kind: ?types.TxBuildKind = null,
    tx_build_package: ?[]const u8 = null,
    tx_build_module: ?[]const u8 = null,
    tx_build_function: ?[]const u8 = null,
    tx_build_type_args: ?[]const u8 = null,
    tx_build_args: ?[]const u8 = null,
    tx_build_sender: ?[]const u8 = null,
    tx_build_gas_budget: ?u64 = null,
    tx_build_gas_price: ?u64 = null,
    tx_build_gas_payment: ?[]const u8 = null,
    tx_build_auto_gas_payment: bool = false,

    // Account options
    account_selector: ?[]const u8 = null,
    account_list_json: bool = false,
    account_info_json: bool = false,
    account_coins_json: bool = false,
    account_objects_json: bool = false,

    // Wallet options
    wallet_alias: ?[]const u8 = null,
    wallet_private_key: ?[]const u8 = null,
    wallet_activate: bool = true,

    // Move options
    move_package: ?[]const u8 = null,
    move_module: ?[]const u8 = null,
    move_function: ?[]const u8 = null,
    move_function_template_output: ?types.MoveFunctionTemplateOutput = null,
    move_summarize: bool = false,

    // Summarize option (global)
    summarize: bool = false,

    // Wallet fund options
    wallet_fund_amount: ?u64 = null,
    wallet_fund_dry_run: bool = false,

    // Object dynamic fields options
    object_dynamic_fields_limit: ?u32 = null,

    // Object options
    object_id: ?[]const u8 = null,
    object_options: ?[]const u8 = null,

    // Event options
    event_filter: ?[]const u8 = null,
    event_package: ?[]const u8 = null,
    event_module: ?[]const u8 = null,
    event_limit: ?u64 = null,

    // Keystore options
    from_keystore: bool = false,
    signatures: std.ArrayListUnmanaged([]const u8) = .{},

    // Owned strings (need cleanup)
    owned_rpc_url: ?[]const u8 = null,
    owned_params: ?[]const u8 = null,
    owned_tx_bytes: ?[]const u8 = null,
    owned_tx_options: ?[]const u8 = null,
    owned_wallet_alias: ?[]const u8 = null,
    owned_wallet_private_key: ?[]const u8 = null,
    owned_account_selector: ?[]const u8 = null,
    owned_signatures: std.ArrayListUnmanaged([]const u8) = .{},

    /// Initialize with allocator
    pub fn init(allocator: std.mem.Allocator) ParsedArgs {
        _ = allocator;
        return .{};
    }

    /// Deinitialize and free owned memory
    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.owned_rpc_url) |v| allocator.free(v);
        if (self.owned_params) |v| allocator.free(v);
        if (self.owned_tx_bytes) |v| allocator.free(v);
        if (self.owned_tx_options) |v| allocator.free(v);
        if (self.owned_wallet_alias) |v| allocator.free(v);
        if (self.owned_wallet_private_key) |v| allocator.free(v);
        if (self.owned_account_selector) |v| allocator.free(v);

        for (self.signatures.items) |sig| allocator.free(sig);
        self.signatures.deinit(allocator);

        for (self.owned_signatures.items) |sig| allocator.free(sig);
        self.owned_signatures.deinit(allocator);
    }

    /// Set RPC URL (takes ownership)
    pub fn setRpcUrl(self: *ParsedArgs, allocator: std.mem.Allocator, url: []const u8) !void {
        if (self.owned_rpc_url) |v| allocator.free(v);
        self.owned_rpc_url = try allocator.dupe(u8, url);
        self.rpc_url = self.owned_rpc_url.?;
        self.has_rpc_url = true;
    }

    /// Add signature
    pub fn addSignature(self: *ParsedArgs, allocator: std.mem.Allocator, signature: []const u8) !void {
        const owned = try allocator.dupe(u8, signature);
        try self.signatures.append(allocator, owned);
        try self.owned_signatures.append(allocator, owned);
    }

    const has_rpc_url: bool = false,
};

/// Check if parsed args has move call arguments
pub fn hasMoveCallArgs(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_package != null or
        parsed.tx_build_module != null or
        parsed.tx_build_function != null;
}

/// Check if parsed args has complete move call arguments
pub fn hasCompleteMoveCallArgs(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_package != null and
        parsed.tx_build_module != null and
        parsed.tx_build_function != null;
}

/// Check if parsed args has programmatic transaction input
pub fn hasProgrammaticTxInput(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_commands != null or
        parsed.tx_build_command_items.items.len > 0;
}

/// Validate programmatic transaction input
pub fn validateProgrammaticTxInput(parsed: *const ParsedArgs) !void {
    if (parsed.tx_build_kind == null) return error.InvalidCli;

    switch (parsed.tx_build_kind.?) {
        .move_call => {
            if (!hasCompleteMoveCallArgs(parsed)) return error.InvalidCli;
        },
        .programmable => {
            if (!hasProgrammaticTxInput(parsed)) return error.InvalidCli;
        },
    }
}

/// Check if command supports programmable input
pub fn supportsProgrammableInput(parsed: *const ParsedArgs) bool {
    return switch (parsed.command) {
        .tx_build,
        .tx_simulate,
        .tx_dry_run,
        .tx_send,
        => true,
        else => false,
    };
}

// ============================================================
// Tests
// ============================================================

test "ParsedArgs lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = ParsedArgs.init(allocator);
    defer args.deinit(allocator);

    try testing.expectEqual(types.Command.help, args.command);
    try testing.expect(!args.has_command);
}

test "ParsedArgs setRpcUrl" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = ParsedArgs.init(allocator);
    defer args.deinit(allocator);

    try args.setRpcUrl(allocator, "https://custom.rpc.com");
    try testing.expectEqualStrings("https://custom.rpc.com", args.rpc_url);
    try testing.expect(args.has_rpc_url);
}

test "ParsedArgs addSignature" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = ParsedArgs.init(allocator);
    defer args.deinit(allocator);

    try args.addSignature(allocator, "sig1");
    try args.addSignature(allocator, "sig2");

    try testing.expectEqual(@as(usize, 2), args.signatures.items.len);
    try testing.expectEqualStrings("sig1", args.signatures.items[0]);
}

test "hasMoveCallArgs detection" {
    const testing = std.testing;

    var args1 = ParsedArgs{ .tx_build_package = "0x1" };
    try testing.expect(hasMoveCallArgs(&args1));

    var args2 = ParsedArgs{};
    try testing.expect(!hasMoveCallArgs(&args2));
}

test "hasCompleteMoveCallArgs detection" {
    const testing = std.testing;

    var args1 = ParsedArgs{
        .tx_build_package = "0x1",
        .tx_build_module = "module",
        .tx_build_function = "func",
    };
    try testing.expect(hasCompleteMoveCallArgs(&args1));

    var args2 = ParsedArgs{
        .tx_build_package = "0x1",
        .tx_build_module = "module",
    };
    try testing.expect(!hasCompleteMoveCallArgs(&args2));
}

test "validateProgrammaticTxInput" {
    const testing = std.testing;

    // Valid move_call
    var args1 = ParsedArgs{
        .tx_build_kind = .move_call,
        .tx_build_package = "0x1",
        .tx_build_module = "module",
        .tx_build_function = "func",
    };
    try validateProgrammaticTxInput(&args1);

    // Invalid move_call (missing args)
    var args2 = ParsedArgs{
        .tx_build_kind = .move_call,
        .tx_build_package = "0x1",
    };
    try testing.expectError(error.InvalidCli, validateProgrammaticTxInput(&args2));

    // Invalid programmable (no commands)
    var args3 = ParsedArgs{
        .tx_build_kind = .programmable,
    };
    try testing.expectError(error.InvalidCli, validateProgrammaticTxInput(&args3));
}

test "supportsProgrammableInput" {
    const testing = std.testing;

    var args1 = ParsedArgs{ .command = .tx_build };
    try testing.expect(supportsProgrammableInput(&args1));

    var args2 = ParsedArgs{ .command = .help };
    try testing.expect(!supportsProgrammableInput(&args2));
}
