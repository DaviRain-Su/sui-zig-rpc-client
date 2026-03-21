/// cli/parser.zig - Command line argument parsing
const std = @import("std");
const types = @import("types.zig");
const parsed_args = @import("parsed_args.zig");

const ParsedArgs = parsed_args.ParsedArgs;

/// Parse command line arguments
pub fn parseCliArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    var parsed: ParsedArgs = .{};
    var parsed_ok = false;
    errdefer if (!parsed_ok) parsed.deinit(allocator);

    if (args.len == 0) {
        parsed.show_usage = true;
        parsed.command = .help;
        parsed_ok = true;
        return parsed;
    }

    var i: usize = 0;
    while (i < args.len) {
        const token = args[i];

        // Global flags
        if (try parseGlobalFlag(&parsed, allocator, args, &i)) continue;

        // Commands
        if (!parsed.has_command) {
            if (try parseCommand(&parsed, allocator, args, &i)) continue;
        }

        // Unknown argument
        return error.InvalidCli;
    }

    // Default to help if no command
    if (!parsed.has_command) {
        parsed.show_usage = true;
        parsed.command = .help;
    }

    parsed_ok = true;
    return parsed;
}

/// Parse global flags (--help, --version, --rpc, etc.)
fn parseGlobalFlag(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    const token = args[i.*];

    if (std.mem.eql(u8, token, "-h") or std.mem.eql(u8, token, "--help")) {
        parsed.show_usage = true;
        parsed.command = .help;
        i.* += 1;
        return true;
    }

    if (std.mem.eql(u8, token, "--version")) {
        parsed.command = .version;
        parsed.has_command = true;
        i.* += 1;
        return true;
    }

    if (std.mem.eql(u8, token, "--rpc")) {
        if (i.* + 1 >= args.len) return error.InvalidCli;
        try parsed.setRpcUrl(allocator, args[i.* + 1]);
        i.* += 2;
        return true;
    }

    if (std.mem.eql(u8, token, "--timeout-ms")) {
        if (i.* + 1 >= args.len) return error.InvalidCli;
        parsed.request_timeout_ms = try parseIntValue(args[i.* + 1]);
        i.* += 2;
        return true;
    }

    if (std.mem.eql(u8, token, "--confirm-timeout-ms")) {
        if (i.* + 1 >= args.len) return error.InvalidCli;
        parsed.confirm_timeout_ms = try parseIntValue(args[i.* + 1]);
        i.* += 2;
        return true;
    }

    if (std.mem.eql(u8, token, "--pretty")) {
        parsed.pretty = true;
        i.* += 1;
        return true;
    }

    if (std.mem.eql(u8, token, "--poll-ms")) {
        if (i.* + 1 >= args.len) return error.InvalidCli;
        parsed.confirm_poll_ms = try parseIntValue(args[i.* + 1]);
        if (parsed.confirm_poll_ms == 0) return error.InvalidCli;
        i.* += 2;
        return true;
    }

    return false;
}

/// Parse commands and their arguments
fn parseCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    const token = args[i.*];

    // Help and version
    if (std.mem.eql(u8, token, "help")) {
        parsed.command = .help;
        parsed.has_command = true;
        i.* += 1;
        return true;
    }

    if (std.mem.eql(u8, token, "version")) {
        parsed.command = .version;
        parsed.has_command = true;
        i.* += 1;
        return true;
    }

    // RPC command
    if (std.mem.eql(u8, token, "rpc")) {
        return try parseRpcCommand(parsed, allocator, args, i);
    }

    // Wallet commands
    if (std.mem.eql(u8, token, "wallet")) {
        return try parseWalletCommand(parsed, allocator, args, i);
    }

    // Account commands
    if (std.mem.eql(u8, token, "account")) {
        return try parseAccountCommand(parsed, allocator, args, i);
    }

    // Transaction commands
    if (std.mem.eql(u8, token, "tx")) {
        return try parseTxCommand(parsed, allocator, args, i);
    }

    // Move commands
    if (std.mem.eql(u8, token, "move")) {
        return try parseMoveCommand(parsed, allocator, args, i);
    }

    // Object commands
    if (std.mem.eql(u8, token, "object")) {
        return try parseObjectCommand(parsed, allocator, args, i);
    }

    return false;
}

/// Parse RPC command
fn parseRpcCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* + 1 >= args.len) return error.InvalidCli;

    parsed.command = .rpc;
    parsed.has_command = true;
    i.* += 1;

    parsed.method = args[i.*];
    i.* += 1;

    if (i.* < args.len and !std.mem.startsWith(u8, args[i.*], "--")) {
        parsed.params = args[i.*];
        i.* += 1;
    } else {
        parsed.params = "[]";
    }

    // Parse RPC-specific flags
    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--summarize")) {
            // TODO: Add summarize flag to ParsedArgs
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse wallet commands
fn parseWalletCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* + 1 >= args.len) return error.InvalidCli;

    const sub = args[i.* + 1];
    i.* += 2;

    if (std.mem.eql(u8, sub, "create")) {
        parsed.command = .wallet_create;
        parsed.has_command = true;
        return try parseWalletCreateArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "import")) {
        parsed.command = .wallet_import;
        parsed.has_command = true;
        return try parseWalletImportArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "use")) {
        parsed.command = .wallet_use;
        parsed.has_command = true;
        return try parseWalletUseArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "accounts")) {
        parsed.command = .wallet_accounts;
        parsed.has_command = true;
        return try parseWalletAccountsArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "connect")) {
        parsed.command = .wallet_connect;
        parsed.has_command = true;
        return true;
    }

    if (std.mem.eql(u8, sub, "disconnect")) {
        parsed.command = .wallet_disconnect;
        parsed.has_command = true;
        return true;
    }

    if (std.mem.eql(u8, sub, "fund")) {
        parsed.command = .wallet_fund;
        parsed.has_command = true;
        return try parseWalletFundArgs(parsed, allocator, args, i);
    }

    return error.InvalidCli;
}

/// Parse wallet create arguments
fn parseWalletCreateArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--alias")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.wallet_alias = args[i.* + 1];
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--no-activate")) {
            parsed.wallet_activate = false;
            i.* += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--json")) {
            parsed.wallet_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse wallet import arguments
fn parseWalletImportArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    // First positional arg is the private key
    parsed.wallet_private_key = args[i.*];
    i.* += 1;

    return try parseWalletCreateArgs(parsed, allocator, args, i);
}

/// Parse wallet use arguments
fn parseWalletUseArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    parsed.wallet_alias = args[i.*];
    i.* += 1;

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--json")) {
            parsed.wallet_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse wallet accounts arguments
fn parseWalletAccountsArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--json")) {
            parsed.wallet_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse wallet fund arguments
fn parseWalletFundArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--amount")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            // TODO: Add wallet_fund_amount to ParsedArgs
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--dry-run")) {
            // TODO: Add wallet_fund_dry_run to ParsedArgs
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse account commands
fn parseAccountCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* + 1 >= args.len) return error.InvalidCli;

    const sub = args[i.* + 1];
    i.* += 2;

    if (std.mem.eql(u8, sub, "list")) {
        parsed.command = .account_list;
        parsed.has_command = true;
        return try parseAccountListArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "info")) {
        parsed.command = .account_info;
        parsed.has_command = true;
        return try parseAccountInfoArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "balance")) {
        parsed.command = .account_balance;
        parsed.has_command = true;
        return try parseAccountBalanceArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "coins")) {
        parsed.command = .account_coins;
        parsed.has_command = true;
        return try parseAccountCoinsArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "objects")) {
        parsed.command = .account_objects;
        parsed.has_command = true;
        return try parseAccountObjectsArgs(parsed, allocator, args, i);
    }

    return error.InvalidCli;
}

/// Parse account list arguments
fn parseAccountListArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--json")) {
            parsed.account_list_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse account info arguments
fn parseAccountInfoArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* < args.len and !std.mem.startsWith(u8, args[i.*], "--")) {
        parsed.account_selector = args[i.*];
        i.* += 1;
    }

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--json")) {
            parsed.account_info_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse account balance arguments
fn parseAccountBalanceArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    return try parseAccountInfoArgs(parsed, allocator, args, i);
}

/// Parse account coins arguments
fn parseAccountCoinsArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* < args.len and !std.mem.startsWith(u8, args[i.*], "--")) {
        parsed.account_selector = args[i.*];
        i.* += 1;
    }

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--json")) {
            parsed.account_coins_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse account objects arguments
fn parseAccountObjectsArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* < args.len and !std.mem.startsWith(u8, args[i.*], "--")) {
        parsed.account_selector = args[i.*];
        i.* += 1;
    }

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--json")) {
            parsed.account_objects_json = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse transaction commands
fn parseTxCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    const sub = args[i.*];
    i.* += 1;

    if (std.mem.eql(u8, sub, "simulate")) {
        parsed.command = .tx_simulate;
        parsed.has_command = true;
        return try parseTxSimulateArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "dry-run") or std.mem.eql(u8, sub, "dry_run")) {
        parsed.command = .tx_dry_run;
        parsed.has_command = true;
        return try parseTxDryRunArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "build")) {
        parsed.command = .tx_build;
        parsed.has_command = true;
        return try parseTxBuildArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "send")) {
        parsed.command = .tx_send;
        parsed.has_command = true;
        return try parseTxSendArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "payload")) {
        parsed.command = .tx_payload;
        parsed.has_command = true;
        return try parseTxPayloadArgs(parsed, allocator, args, i);
    }

    return error.InvalidCli;
}

/// Parse tx simulate arguments
fn parseTxSimulateArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* < args.len and !std.mem.startsWith(u8, args[i.*], "--")) {
        parsed.tx_bytes = args[i.*];
        i.* += 1;
    }

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--summarize")) {
            parsed.tx_send_summarize = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse tx dry-run arguments
fn parseTxDryRunArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    return try parseTxSimulateArgs(parsed, allocator, args, i);
}

/// Parse tx build arguments
fn parseTxBuildArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--kind")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            const kind_str = args[i.* + 1];
            if (std.mem.eql(u8, kind_str, "move-call")) {
                parsed.tx_build_kind = .move_call;
            } else if (std.mem.eql(u8, kind_str, "programmable")) {
                parsed.tx_build_kind = .programmable;
            } else {
                return error.InvalidCli;
            }
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--package")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.tx_build_package = args[i.* + 1];
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--module")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.tx_build_module = args[i.* + 1];
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--function")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.tx_build_function = args[i.* + 1];
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--sender")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.tx_build_sender = args[i.* + 1];
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--gas-budget")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.tx_build_gas_budget = try parseIntValue(args[i.* + 1]);
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--summarize")) {
            parsed.tx_send_summarize = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse tx send arguments
fn parseTxSendArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* < args.len and !std.mem.startsWith(u8, args[i.*], "--")) {
        parsed.tx_bytes = args[i.*];
        i.* += 1;
    }

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--signature")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            try parsed.addSignature(allocator, args[i.* + 1]);
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--wait")) {
            parsed.tx_send_wait = true;
            i.* += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--summarize")) {
            parsed.tx_send_summarize = true;
            i.* += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--observe")) {
            parsed.tx_send_observe = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse tx payload arguments
fn parseTxPayloadArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    return try parseTxSendArgs(parsed, allocator, args, i);
}

/// Parse Move commands
fn parseMoveCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    const sub = args[i.*];
    i.* += 1;

    if (std.mem.eql(u8, sub, "package")) {
        parsed.command = .move_package;
        parsed.has_command = true;
        return try parseMovePackageArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "module")) {
        parsed.command = .move_module;
        parsed.has_command = true;
        return try parseMoveModuleArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "function")) {
        parsed.command = .move_function;
        parsed.has_command = true;
        return try parseMoveFunctionArgs(parsed, allocator, args, i);
    }

    return error.InvalidCli;
}

/// Parse move package arguments
fn parseMovePackageArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    parsed.move_package = args[i.*];
    i.* += 1;

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--summarize")) {
            parsed.move_summarize = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse move module arguments
fn parseMoveModuleArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* + 1 >= args.len) return error.InvalidCli;

    parsed.move_package = args[i.*];
    parsed.move_module = args[i.* + 1];
    i.* += 2;

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--summarize")) {
            parsed.move_summarize = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse move function arguments
fn parseMoveFunctionArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* + 2 >= args.len) return error.InvalidCli;

    parsed.move_package = args[i.*];
    parsed.move_module = args[i.* + 1];
    parsed.move_function = args[i.* + 2];
    i.* += 3;

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--output")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            parsed.move_function_template_output = try types.parseMoveFunctionTemplateOutput(args[i.* + 1]);
            i.* += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--summarize")) {
            parsed.move_summarize = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse object commands
fn parseObjectCommand(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    const sub = args[i.*];
    i.* += 1;

    if (std.mem.eql(u8, sub, "get")) {
        parsed.command = .object_get;
        parsed.has_command = true;
        return try parseObjectGetArgs(parsed, allocator, args, i);
    }

    if (std.mem.eql(u8, sub, "dynamic-fields")) {
        parsed.command = .object_dynamic_fields;
        parsed.has_command = true;
        return try parseObjectDynamicFieldsArgs(parsed, allocator, args, i);
    }

    return error.InvalidCli;
}

/// Parse object get arguments
fn parseObjectGetArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    parsed.object_id = args[i.*];
    i.* += 1;

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--show-type")) {
            parsed.object_show_type = true;
            i.* += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--show-content")) {
            parsed.object_show_content = true;
            i.* += 1;
            continue;
        }

        break;
    }

    return true;
}

/// Parse object dynamic fields arguments
fn parseObjectDynamicFieldsArgs(
    parsed: *ParsedArgs,
    allocator: std.mem.Allocator,
    args: []const []const u8,
    i: *usize,
) !bool {
    if (i.* >= args.len) return error.InvalidCli;

    parsed.object_id = args[i.*];
    i.* += 1;

    while (i.* < args.len) {
        const token = args[i.*];

        if (std.mem.eql(u8, token, "--limit")) {
            if (i.* + 1 >= args.len) return error.InvalidCli;
            // TODO: Add object_dynamic_fields_limit to ParsedArgs
            i.* += 2;
            continue;
        }

        break;
    }

    return true;
}

/// Parse integer value
fn parseIntValue(value: []const u8) !u64 {
    return std.fmt.parseInt(u64, value, 10) catch return error.InvalidCli;
}

// ============================================================
// Tests
// ============================================================

test "parseCliArgs with no args returns help" {
    const testing = std.testing;
    const args: []const []const u8 = &{};

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.help, parsed.command);
    try testing.expect(parsed.show_usage);
}

test "parseCliArgs parses help command" {
    const testing = std.testing;
    const args = &.{"help"};

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.help, parsed.command);
    try testing.expect(parsed.has_command);
}

test "parseCliArgs parses version command" {
    const testing = std.testing;
    const args = &.{"--version"};

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.version, parsed.command);
    try testing.expect(parsed.has_command);
}

test "parseCliArgs parses global flags" {
    const testing = std.testing;
    const args = &.{ "--rpc", "https://custom.rpc.com", "--pretty", "--timeout-ms", "5000", "help" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqualStrings("https://custom.rpc.com", parsed.rpc_url);
    try testing.expect(parsed.pretty);
    try testing.expectEqual(@as(u64, 5000), parsed.request_timeout_ms.?);
}

test "parseCliArgs parses rpc command" {
    const testing = std.testing;
    const args = &.{ "rpc", "suix_getBalance", "[\"0x123\"]" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.rpc, parsed.command);
    try testing.expectEqualStrings("suix_getBalance", parsed.method.?);
    try testing.expectEqualStrings("[\"0x123\"]", parsed.params.?);
}

test "parseCliArgs parses wallet create command" {
    const testing = std.testing;
    const args = &.{ "wallet", "create", "--alias", "mywallet", "--json" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.wallet_create, parsed.command);
    try testing.expectEqualStrings("mywallet", parsed.wallet_alias.?);
    try testing.expect(parsed.wallet_json);
}

test "parseCliArgs parses account list command" {
    const testing = std.testing;
    const args = &.{ "account", "list", "--json" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.account_list, parsed.command);
    try testing.expect(parsed.account_list_json);
}

test "parseCliArgs parses tx build command" {
    const testing = std.testing;
    const args = &.{ "tx", "build", "--kind", "move-call", "--package", "0x1", "--module", "module", "--function", "func" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.tx_build, parsed.command);
    try testing.expectEqual(types.TxBuildKind.move_call, parsed.tx_build_kind.?);
    try testing.expectEqualStrings("0x1", parsed.tx_build_package.?);
    try testing.expectEqualStrings("module", parsed.tx_build_module.?);
    try testing.expectEqualStrings("func", parsed.tx_build_function.?);
}

test "parseCliArgs parses tx send command with signatures" {
    const testing = std.testing;
    const args = &.{ "tx", "send", "txbytes", "--signature", "sig1", "--signature", "sig2", "--wait" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.tx_send, parsed.command);
    try testing.expectEqualStrings("txbytes", parsed.tx_bytes.?);
    try testing.expectEqual(@as(usize, 2), parsed.signatures.items.len);
    try testing.expect(parsed.tx_send_wait);
}

test "parseCliArgs parses move package command" {
    const testing = std.testing;
    const args = &.{ "move", "package", "0x1", "--summarize" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.move_package, parsed.command);
    try testing.expectEqualStrings("0x1", parsed.move_package.?);
    try testing.expect(parsed.move_summarize);
}

test "parseCliArgs parses object get command" {
    const testing = std.testing;
    const args = &.{ "object", "get", "0xobj", "--show-content" };

    var parsed = try parseCliArgs(testing.allocator, args);
    defer parsed.deinit(testing.allocator);

    try testing.expectEqual(types.Command.object_get, parsed.command);
    try testing.expectEqualStrings("0xobj", parsed.object_id.?);
    try testing.expect(parsed.object_show_content);
}

test "parseCliArgs rejects unknown command" {
    const testing = std.testing;
    const args = &.{"unknown_command"};

    const result = parseCliArgs(testing.allocator, args);
    try testing.expectError(error.InvalidCli, result);
}

test "parseIntValue parses valid integers" {
    const testing = std.testing;

    try testing.expectEqual(@as(u64, 42), try parseIntValue("42"));
    try testing.expectEqual(@as(u64, 0), try parseIntValue("0"));
    try testing.expectEqual(@as(u64, 999999), try parseIntValue("999999"));
}

test "parseIntValue rejects invalid integers" {
    const testing = std.testing;

    try testing.expectError(error.InvalidCli, parseIntValue("abc"));
    try testing.expectError(error.InvalidCli, parseIntValue(""));
    try testing.expectError(error.InvalidCli, parseIntValue("12.34"));
}
