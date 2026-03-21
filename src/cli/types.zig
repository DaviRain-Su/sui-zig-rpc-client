/// cli/types.zig - CLI type definitions
const std = @import("std");

pub const default_rpc_url = "https://fullnode.mainnet.sui.io:443";

/// Main command enum
pub const Command = enum {
    help,
    version,
    rpc,
    // Wallet commands
    wallet_create,
    wallet_import,
    wallet_use,
    wallet_accounts,
    wallet_connect,
    wallet_disconnect,
    wallet_passkey_list,
    wallet_passkey_register,
    wallet_passkey_login,
    wallet_passkey_revoke,
    wallet_session_create,
    wallet_session_list,
    wallet_session_revoke,
    wallet_policy_inspect,
    wallet_export_public,
    wallet_signer_inspect,
    wallet_address,
    wallet_balance,
    wallet_coins,
    wallet_objects,
    wallet_fund,
    wallet_intent_build,
    wallet_intent_dry_run,
    wallet_intent_send,
    // Account commands
    account_list,
    account_info,
    account_balance,
    account_coins,
    account_objects,
    account_resources,
    // Request lifecycle commands
    request_build,
    request_inspect,
    request_dry_run,
    request_sponsor,
    request_sign,
    request_send,
    request_schedule,
    request_list,
    request_cancel,
    request_resume,
    request_rebroadcast,
    request_status,
    request_confirm,
    // Other commands
    events,
    move_package,
    move_module,
    move_function,
    object_get,
    object_dynamic_fields,
    object_dynamic_field_object,
    tx_simulate,
    tx_dry_run,
    tx_build,
    tx_send,
    tx_payload,
    tx_confirm,
    tx_status,
    natural_do,
};

/// Transaction build kind
pub const TxBuildKind = enum {
    move_call,
    programmable,
};

/// Move function template output format
pub const MoveFunctionTemplateOutput = enum {
    commands,
    preferred_commands,
    tx_dry_run_request,
    preferred_tx_dry_run_request,
    tx_dry_run_argv,
    preferred_tx_dry_run_argv,
    tx_dry_run_command,
    preferred_tx_dry_run_command,
    tx_send_from_keystore_request,
    preferred_tx_send_from_keystore_request,
    tx_send_from_keystore_argv,
    preferred_tx_send_from_keystore_argv,
    tx_send_from_keystore_command,
    preferred_tx_send_from_keystore_command,
};

/// Command categories for organization
pub const CommandCategory = enum {
    wallet,
    account,
    transaction,
    move,
    object,
    request,
    query,
    utility,
};

/// Get category for a command
pub fn getCommandCategory(command: Command) CommandCategory {
    return switch (command) {
        .wallet_create,
        .wallet_import,
        .wallet_use,
        .wallet_accounts,
        .wallet_connect,
        .wallet_disconnect,
        .wallet_passkey_list,
        .wallet_passkey_register,
        .wallet_passkey_login,
        .wallet_passkey_revoke,
        .wallet_session_create,
        .wallet_session_list,
        .wallet_session_revoke,
        .wallet_policy_inspect,
        .wallet_export_public,
        .wallet_signer_inspect,
        .wallet_address,
        .wallet_balance,
        .wallet_coins,
        .wallet_objects,
        .wallet_fund,
        .wallet_intent_build,
        .wallet_intent_dry_run,
        .wallet_intent_send,
        => .wallet,

        .account_list,
        .account_info,
        .account_balance,
        .account_coins,
        .account_objects,
        .account_resources,
        => .account,

        .tx_simulate,
        .tx_dry_run,
        .tx_build,
        .tx_send,
        .tx_payload,
        .tx_confirm,
        .tx_status,
        => .transaction,

        .move_package,
        .move_module,
        .move_function,
        => .move,

        .object_get,
        .object_dynamic_fields,
        .object_dynamic_field_object,
        => .object,

        .request_build,
        .request_inspect,
        .request_dry_run,
        .request_sponsor,
        .request_sign,
        .request_send,
        .request_schedule,
        .request_list,
        .request_cancel,
        .request_resume,
        .request_rebroadcast,
        .request_status,
        .request_confirm,
        => .request,

        .events => .query,

        .help,
        .version,
        .rpc,
        .natural_do,
        => .utility,
    };
}

/// Check if command is a wallet command
pub fn isWalletCommand(command: Command) bool {
    return getCommandCategory(command) == .wallet;
}

/// Check if command is an account command
pub fn isAccountCommand(command: Command) bool {
    return getCommandCategory(command) == .account;
}

/// Check if command is a transaction command
pub fn isTransactionCommand(command: Command) bool {
    return getCommandCategory(command) == .transaction;
}

/// Parse move function template output from string
pub fn parseMoveFunctionTemplateOutput(value: []const u8) !MoveFunctionTemplateOutput {
    if (std.mem.eql(u8, value, "commands")) return .commands;
    if (std.mem.eql(u8, value, "preferred-commands")) return .preferred_commands;
    if (std.mem.eql(u8, value, "dry-run-request")) return .tx_dry_run_request;
    if (std.mem.eql(u8, value, "preferred-dry-run-request")) return .preferred_tx_dry_run_request;
    if (std.mem.eql(u8, value, "dry-run-argv")) return .tx_dry_run_argv;
    if (std.mem.eql(u8, value, "preferred-dry-run-argv")) return .preferred_tx_dry_run_argv;
    if (std.mem.eql(u8, value, "dry-run-command")) return .tx_dry_run_command;
    if (std.mem.eql(u8, value, "preferred-dry-run-command")) return .preferred_tx_dry_run_command;
    if (std.mem.eql(u8, value, "send-request")) return .tx_send_from_keystore_request;
    if (std.mem.eql(u8, value, "preferred-send-request")) return .preferred_tx_send_from_keystore_request;
    if (std.mem.eql(u8, value, "send-argv")) return .tx_send_from_keystore_argv;
    if (std.mem.eql(u8, value, "preferred-send-argv")) return .preferred_tx_send_from_keystore_argv;
    if (std.mem.eql(u8, value, "send-command")) return .tx_send_from_keystore_command;
    if (std.mem.eql(u8, value, "preferred-send-command")) return .preferred_tx_send_from_keystore_command;
    return error.InvalidCli;
}

// ============================================================
// Tests
// ============================================================

test "CommandCategory categorization" {
    const testing = std.testing;

    try testing.expectEqual(CommandCategory.wallet, getCommandCategory(.wallet_create));
    try testing.expectEqual(CommandCategory.account, getCommandCategory(.account_list));
    try testing.expectEqual(CommandCategory.transaction, getCommandCategory(.tx_send));
    try testing.expectEqual(CommandCategory.move, getCommandCategory(.move_package));
    try testing.expectEqual(CommandCategory.object, getCommandCategory(.object_get));
    try testing.expectEqual(CommandCategory.utility, getCommandCategory(.help));
}

test "isWalletCommand detection" {
    const testing = std.testing;

    try testing.expect(isWalletCommand(.wallet_create));
    try testing.expect(isWalletCommand(.wallet_accounts));
    try testing.expect(!isWalletCommand(.account_list));
    try testing.expect(!isWalletCommand(.tx_send));
}

test "parseMoveFunctionTemplateOutput parses valid values" {
    const testing = std.testing;

    try testing.expectEqual(MoveFunctionTemplateOutput.commands, try parseMoveFunctionTemplateOutput("commands"));
    try testing.expectEqual(MoveFunctionTemplateOutput.tx_dry_run_request, try parseMoveFunctionTemplateOutput("dry-run-request"));
    try testing.expectEqual(MoveFunctionTemplateOutput.tx_send_from_keystore_request, try parseMoveFunctionTemplateOutput("send-request"));
}

test "parseMoveFunctionTemplateOutput rejects invalid values" {
    const testing = std.testing;
    try testing.expectError(error.InvalidCli, parseMoveFunctionTemplateOutput("invalid"));
}
