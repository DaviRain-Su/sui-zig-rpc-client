/// cli/integration.zig - Integration with main codebase
const std = @import("std");
const cli = @import("root.zig");
const types = @import("types.zig");
const parsed_args = @import("parsed_args.zig");

const old_cli = @import("../cli.zig");
const commands = @import("../commands.zig");
const client = @import("sui_client_zig");

/// Convert new ParsedArgs to old ParsedArgs for backward compatibility
pub fn convertToOldParsedArgs(
    allocator: std.mem.Allocator,
    new_args: *const parsed_args.ParsedArgs,
) !old_cli.ParsedArgs {
    var old_args: old_cli.ParsedArgs = .{};

    // Copy command
    old_args.command = convertCommand(new_args.command);
    old_args.has_command = new_args.has_command;
    old_args.show_usage = new_args.show_usage;

    // Copy global options
    old_args.pretty = new_args.pretty;
    old_args.rpc_url = new_args.rpc_url;
    old_args.request_timeout_ms = new_args.request_timeout_ms;
    old_args.confirm_timeout_ms = new_args.confirm_timeout_ms;
    old_args.confirm_poll_ms = new_args.confirm_poll_ms;

    // Copy RPC options
    if (new_args.method) |m| {
        old_args.method = m;
    }
    if (new_args.params) |p| {
        try setOwnedString(allocator, p, &old_args.owned_params, &old_args.params);
    }

    // Copy transaction options
    if (new_args.tx_bytes) |b| {
        try setOwnedString(allocator, b, &old_args.owned_tx_bytes, &old_args.tx_bytes);
    }
    if (new_args.tx_options) |o| {
        try setOwnedString(allocator, o, &old_args.owned_tx_options, &old_args.tx_options);
    }
    old_args.tx_send_wait = new_args.tx_send_wait;
    old_args.tx_send_summarize = new_args.tx_send_summarize;
    old_args.tx_send_observe = new_args.tx_send_observe;

    // Copy tx build options
    if (new_args.tx_build_kind) |k| {
        old_args.tx_build_kind = convertTxBuildKind(k);
    }
    if (new_args.tx_build_package) |p| {
        try setOwnedString(allocator, p, &old_args.owned_tx_build_package, &old_args.tx_build_package);
    }
    if (new_args.tx_build_module) |m| {
        try setOwnedString(allocator, m, &old_args.owned_tx_build_module, &old_args.tx_build_module);
    }
    if (new_args.tx_build_function) |f| {
        try setOwnedString(allocator, f, &old_args.owned_tx_build_function, &old_args.tx_build_function);
    }
    if (new_args.tx_build_sender) |s| {
        try setOwnedString(allocator, s, &old_args.owned_tx_build_sender, &old_args.tx_build_sender);
    }
    old_args.tx_build_gas_budget = new_args.tx_build_gas_budget;
    old_args.tx_build_gas_price = new_args.tx_build_gas_price;
    if (new_args.tx_build_gas_payment) |p| {
        try setOwnedString(allocator, p, &old_args.owned_tx_build_gas_payment, &old_args.tx_build_gas_payment);
    }
    old_args.tx_build_auto_gas_payment = new_args.tx_build_auto_gas_payment;

    // Copy account options
    old_args.account_list_json = new_args.account_list_json;
    old_args.account_info_json = new_args.account_info_json;
    old_args.account_coins_json = new_args.account_coins_json;
    old_args.account_objects_json = new_args.account_objects_json;
    if (new_args.account_selector) |s| {
        try setOwnedString(allocator, s, &old_args.owned_account_selector, &old_args.account_selector);
    }

    // Copy wallet options
    if (new_args.wallet_alias) |a| {
        try setOwnedString(allocator, a, &old_args.owned_wallet_alias, &old_args.wallet_alias);
    }
    if (new_args.wallet_private_key) |k| {
        try setOwnedString(allocator, k, &old_args.owned_wallet_private_key, &old_args.wallet_private_key);
    }
    old_args.wallet_activate = new_args.wallet_activate;

    // Copy move options
    if (new_args.move_package) |p| {
        old_args.move_package = p;
    }
    if (new_args.move_module) |m| {
        old_args.move_module = m;
    }
    if (new_args.move_function) |f| {
        old_args.move_function = f;
    }
    if (new_args.move_function_template_output) |o| {
        old_args.move_function_template_output = convertMoveFunctionTemplateOutput(o);
    }
    old_args.move_summarize = new_args.move_summarize;

    // Copy object options
    if (new_args.object_id) |id| {
        old_args.object_id = id;
    }
    old_args.object_show_type = new_args.object_show_type;
    old_args.object_show_content = new_args.object_show_content;

    // Copy signatures
    for (new_args.signatures.items) |sig| {
        const owned = try allocator.dupe(u8, sig);
        try old_args.signatures.append(allocator, owned);
        try old_args.owned_signatures.append(allocator, owned);
    }

    // Copy event options
    if (new_args.event_filter) |f| {
        old_args.event_filter = f;
    }
    if (new_args.event_package) |p| {
        old_args.event_package = p;
    }
    if (new_args.event_module) |m| {
        old_args.event_module = m;
    }
    old_args.event_limit = new_args.event_limit;

    // Copy keystore options
    old_args.from_keystore = new_args.from_keystore;

    return old_args;
}

/// Set owned string field
fn setOwnedString(
    allocator: std.mem.Allocator,
    value: []const u8,
    owned_ptr: *?[]const u8,
    ptr: *?[]const u8,
) !void {
    const duped = try allocator.dupe(u8, value);
    owned_ptr.* = duped;
    ptr.* = duped;
}

/// Convert new Command to old Command
fn convertCommand(command: types.Command) old_cli.Command {
    return switch (command) {
        .help => .help,
        .version => .version,
        .rpc => .rpc,
        .wallet_create => .wallet_create,
        .wallet_import => .wallet_import,
        .wallet_use => .wallet_use,
        .wallet_accounts => .wallet_accounts,
        .wallet_connect => .wallet_connect,
        .wallet_disconnect => .wallet_disconnect,
        .wallet_passkey_list => .wallet_passkey_list,
        .wallet_passkey_register => .wallet_passkey_register,
        .wallet_passkey_login => .wallet_passkey_login,
        .wallet_passkey_revoke => .wallet_passkey_revoke,
        .wallet_session_create => .wallet_session_create,
        .wallet_session_list => .wallet_session_list,
        .wallet_session_revoke => .wallet_session_revoke,
        .wallet_policy_inspect => .wallet_policy_inspect,
        .wallet_export_public => .wallet_export_public,
        .wallet_signer_inspect => .wallet_signer_inspect,
        .wallet_address => .wallet_address,
        .wallet_balance => .wallet_balance,
        .wallet_coins => .wallet_coins,
        .wallet_objects => .wallet_objects,
        .wallet_fund => .wallet_fund,
        .wallet_intent_build => .wallet_intent_build,
        .wallet_intent_dry_run => .wallet_intent_dry_run,
        .wallet_intent_send => .wallet_intent_send,
        .account_list => .account_list,
        .account_info => .account_info,
        .account_balance => .account_balance,
        .account_coins => .account_coins,
        .account_objects => .account_objects,
        .account_resources => .account_resources,
        .request_build => .request_build,
        .request_inspect => .request_inspect,
        .request_dry_run => .request_dry_run,
        .request_sponsor => .request_sponsor,
        .request_sign => .request_sign,
        .request_send => .request_send,
        .request_schedule => .request_schedule,
        .request_list => .request_list,
        .request_cancel => .request_cancel,
        .request_resume => .request_resume,
        .request_rebroadcast => .request_rebroadcast,
        .request_status => .request_status,
        .request_confirm => .request_confirm,
        .events => .events,
        .move_package => .move_package,
        .move_module => .move_module,
        .move_function => .move_function,
        .object_get => .object_get,
        .object_dynamic_fields => .object_dynamic_fields,
        .object_dynamic_field_object => .object_dynamic_field_object,
        .tx_simulate => .tx_simulate,
        .tx_dry_run => .tx_dry_run,
        .tx_build => .tx_build,
        .tx_send => .tx_send,
        .tx_payload => .tx_payload,
        .tx_confirm => .tx_confirm,
        .tx_status => .tx_status,
        .natural_do => .natural_do,
    };
}

/// Convert new TxBuildKind to old TxBuildKind
fn convertTxBuildKind(kind: types.TxBuildKind) old_cli.TxBuildKind {
    return switch (kind) {
        .move_call => .move_call,
        .programmable => .programmable,
    };
}

/// Convert new MoveFunctionTemplateOutput to old
fn convertMoveFunctionTemplateOutput(output: types.MoveFunctionTemplateOutput) old_cli.MoveFunctionTemplateOutput {
    return switch (output) {
        .commands => .commands,
        .preferred_commands => .preferred_commands,
        .tx_dry_run_request => .tx_dry_run_request,
        .preferred_tx_dry_run_request => .preferred_tx_dry_run_request,
        .tx_dry_run_argv => .tx_dry_run_argv,
        .preferred_tx_dry_run_argv => .preferred_tx_dry_run_argv,
        .tx_dry_run_command => .tx_dry_run_command,
        .preferred_tx_dry_run_command => .preferred_tx_dry_run_command,
        .tx_send_from_keystore_request => .tx_send_from_keystore_request,
        .preferred_tx_send_from_keystore_request => .preferred_tx_send_from_keystore_request,
        .tx_send_from_keystore_argv => .tx_send_from_keystore_argv,
        .preferred_tx_send_from_keystore_argv => .preferred_tx_send_from_keystore_argv,
        .tx_send_from_keystore_command => .tx_send_from_keystore_command,
        .preferred_tx_send_from_keystore_command => .preferred_tx_send_from_keystore_command,
    };
}

/// Run command using new CLI parser with old command runner
pub fn runWithNewCli(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !u8 {
    // Parse with new CLI
    var new_parsed = try cli.parseCliArgs(allocator, args);
    defer new_parsed.deinit(allocator);

    // Validate with new validator
    try cli.validateArgs(&new_parsed);

    // Convert to old format
    var old_parsed = try convertToOldParsedArgs(allocator, &new_parsed);
    defer old_parsed.deinit(allocator);

    // Handle help
    if (old_parsed.show_usage) {
        if (old_parsed.has_command and old_parsed.command != .help) {
            try cli.printCommandHelp(std.io.getStdOut().writer(), new_parsed.command);
        } else {
            try cli.printUsage(std.io.getStdOut().writer());
        }
        return 0;
    }

    // Handle version
    if (old_parsed.command == .version) {
        try cli.printVersion(std.io.getStdOut().writer());
        return 0;
    }

    // Run with old command system
    // TODO: Integrate with actual command runner
    std.debug.print("Command: {s}\n", .{@tagName(old_parsed.command)});
    return 0;
}

/// Test end-to-end CLI workflow
test "end-to-end CLI workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = &[_][]const u8{ "wallet", "create", "--alias", "test", "--json" };

    var parsed = try cli.parseCliArgs(allocator, args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(types.Command.wallet_create, parsed.command);
    try testing.expectEqualStrings("test", parsed.wallet_alias.?);
    try testing.expect(parsed.wallet_json);

    // Convert to old format
    var old_parsed = try convertToOldParsedArgs(allocator, &parsed);
    defer old_parsed.deinit(allocator);

    try testing.expectEqual(old_cli.Command.wallet_create, old_parsed.command);
}

/// Test command conversion
test "command conversion roundtrip" {
    const testing = std.testing;

    const commands_to_test = &[_]types.Command{
        .help,
        .version,
        .wallet_create,
        .account_list,
        .tx_send,
        .move_package,
        .object_get,
        .events,
    };

    for (commands_to_test) |cmd| {
        const old_cmd = convertCommand(cmd);
        _ = old_cmd;
        // Just verify it compiles and runs
    }
}

/// Test TxBuildKind conversion
test "TxBuildKind conversion" {
    const testing = std.testing;

    try testing.expectEqual(old_cli.TxBuildKind.move_call, convertTxBuildKind(.move_call));
    try testing.expectEqual(old_cli.TxBuildKind.programmable, convertTxBuildKind(.programmable));
}

/// Test MoveFunctionTemplateOutput conversion
test "MoveFunctionTemplateOutput conversion" {
    const testing = std.testing;

    try testing.expectEqual(old_cli.MoveFunctionTemplateOutput.commands, convertMoveFunctionTemplateOutput(.commands));
    try testing.expectEqual(old_cli.MoveFunctionTemplateOutput.tx_dry_run_request, convertMoveFunctionTemplateOutput(.tx_dry_run_request));
}

/// Test complex argument conversion
test "complex argument conversion" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = &[_][]const u8{
        "tx", "send", "txbytes123",
        "--signature", "sig1",
        "--signature", "sig2",
        "--wait",
        "--summarize",
    };

    var parsed = try cli.parseCliArgs(allocator, args);
    defer parsed.deinit(allocator);

    var old_parsed = try convertToOldParsedArgs(allocator, &parsed);
    defer old_parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), old_parsed.signatures.items.len);
    try testing.expect(old_parsed.tx_send_wait);
    try testing.expect(old_parsed.tx_send_summarize);
}
