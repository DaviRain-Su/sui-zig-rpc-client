const std = @import("std");
const sui = @import("sui_client_zig");
const object_preset = sui.object_preset;
const package_preset = sui.package_preset;
const tx_builder = sui.tx_builder;
const tx_request_builder = sui.tx_request_builder;
const wallet_intent = @import("./wallet_intent.zig");

pub const default_rpc_url = "https://fullnode.mainnet.sui.io:443";
pub var test_stdin_value_override: ?[]const u8 = null;

pub const Command = enum {
    help,
    version,
    rpc,
    wallet_create,
    wallet_import,
    wallet_use,
    wallet_export_public,
    wallet_signer_inspect,
    wallet_address,
    wallet_balance,
    wallet_coins,
    wallet_objects,
    wallet_intent_build,
    wallet_intent_dry_run,
    wallet_intent_send,
    account_list,
    account_info,
    account_coins,
    account_objects,
    account_resources,
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
};

pub const TxBuildKind = enum {
    move_call,
    programmable,
};

pub const MoveFunctionTemplateOutput = enum {
    commands,
    preferred_commands,
    tx_dry_run_request,
    preferred_tx_dry_run_request,
    tx_send_from_keystore_request,
    preferred_tx_send_from_keystore_request,
};

pub const ParsedArgs = struct {
    command: Command = .help,
    has_command: bool = false,
    show_usage: bool = false,
    has_rpc_url: bool = false,
    pretty: bool = false,
    rpc_url: []const u8 = default_rpc_url,
    method: ?[]const u8 = null,
    params: ?[]const u8 = null,
    tx_bytes: ?[]const u8 = null,
    tx_options: ?[]const u8 = null,
    tx_digest: ?[]const u8 = null,
    tx_build_kind: ?TxBuildKind = null,
    tx_build_package: ?[]const u8 = null,
    tx_build_module: ?[]const u8 = null,
    tx_build_function: ?[]const u8 = null,
    tx_build_type_args: ?[]const u8 = null,
    tx_build_args: ?[]const u8 = null,
    tx_build_commands: ?[]const u8 = null,
    tx_build_command_items: std.ArrayListUnmanaged([]const u8) = .{},
    tx_build_type_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    tx_build_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    tx_build_sender: ?[]const u8 = null,
    tx_build_gas_budget: ?u64 = null,
    tx_build_gas_price: ?u64 = null,
    tx_build_gas_payment: ?[]const u8 = null,
    tx_build_auto_gas_payment: bool = false,
    tx_build_auto_gas_budget: bool = false,
    tx_build_gas_payment_min_balance: ?u64 = null,
    tx_build_emit_tx_block: bool = false,
    account_list_json: bool = false,
    account_info_json: bool = false,
    account_coins_json: bool = false,
    account_objects_json: bool = false,
    account_resources_json: bool = false,
    wallet_json: bool = false,
    events_json: bool = false,
    account_selector: ?[]const u8 = null,
    wallet_alias: ?[]const u8 = null,
    wallet_private_key: ?[]const u8 = null,
    wallet_activate: bool = true,
    intent_network: ?[]const u8 = null,
    intent_execution_mode: ?[]const u8 = null,
    intent_policy_json: ?[]const u8 = null,
    request_sponsor_mode: ?[]const u8 = null,
    request_sponsor_policy: ?[]const u8 = null,
    request_valid_after_ms: ?u64 = null,
    request_valid_before_ms: ?u64 = null,
    request_correlation_id: ?[]const u8 = null,
    request_entry_id: ?[]const u8 = null,
    request_schedule_id: ?[]const u8 = null,
    request_schedule_replace_id: ?[]const u8 = null,
    request_schedule_at_ms: ?u64 = null,
    account_coin_type: ?[]const u8 = null,
    account_coins_cursor: ?[]const u8 = null,
    account_coins_limit: ?u64 = null,
    account_coins_all: bool = false,
    account_objects_filter: ?[]const u8 = null,
    account_objects_struct_type: ?[]const u8 = null,
    account_objects_object_id: ?[]const u8 = null,
    account_objects_package: ?[]const u8 = null,
    account_objects_module: ?[]const u8 = null,
    account_objects_cursor: ?[]const u8 = null,
    account_objects_limit: ?u64 = null,
    account_objects_all: bool = false,
    account_resources_limit: ?u64 = null,
    account_resources_all: bool = false,
    event_filter: ?[]const u8 = null,
    event_package: ?[]const u8 = null,
    event_module: ?[]const u8 = null,
    event_type: ?[]const u8 = null,
    event_sender: ?[]const u8 = null,
    event_tx_digest_filter: ?[]const u8 = null,
    event_cursor_tx_digest: ?[]const u8 = null,
    event_cursor_event_seq: ?u64 = null,
    event_limit: ?u64 = null,
    event_all: bool = false,
    event_descending: bool = false,
    move_package: ?[]const u8 = null,
    move_module: ?[]const u8 = null,
    move_function: ?[]const u8 = null,
    move_function_template_output: ?MoveFunctionTemplateOutput = null,
    move_function_execute_dry_run: bool = false,
    move_function_execute_send: bool = false,
    move_function_indexed_arg_indices: std.ArrayListUnmanaged(usize) = .{},
    move_function_indexed_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_move_function_indexed_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    move_function_indexed_args_json: ?[]const u8 = null,
    owned_move_function_indexed_args_json: ?[]const u8 = null,
    move_function_indexed_object_arg_indices: std.ArrayListUnmanaged(usize) = .{},
    move_function_indexed_object_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_move_function_indexed_object_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    move_function_indexed_object_args_json: ?[]const u8 = null,
    owned_move_function_indexed_object_args_json: ?[]const u8 = null,
    object_id: ?[]const u8 = null,
    object_parent_id: ?[]const u8 = null,
    object_dynamic_field_name: ?[]const u8 = null,
    object_dynamic_field_name_type: ?[]const u8 = null,
    object_dynamic_field_name_value: ?[]const u8 = null,
    object_dynamic_fields_cursor: ?[]const u8 = null,
    object_dynamic_fields_limit: ?u64 = null,
    object_dynamic_fields_all: bool = false,
    object_options: ?[]const u8 = null,
    object_show_type: bool = false,
    object_show_owner: bool = false,
    object_show_previous_transaction: bool = false,
    object_show_display: bool = false,
    object_show_content: bool = false,
    object_show_bcs: bool = false,
    object_show_storage_rebate: bool = false,
    request_timeout_ms: ?u64 = null,
    confirm_timeout_ms: ?u64 = null,
    confirm_poll_ms: u64 = 2_000,
    tx_send_wait: bool = false,
    tx_send_summarize: bool = false,
    tx_send_observe: bool = false,
    tx_session_response: ?[]const u8 = null,
    tx_provider_config: ?[]const u8 = null,
    from_keystore: bool = false,
    owned_rpc_url: ?[]const u8 = null,
    owned_params: ?[]const u8 = null,
    owned_tx_bytes: ?[]const u8 = null,
    owned_tx_options: ?[]const u8 = null,
    owned_tx_build_package: ?[]const u8 = null,
    owned_tx_build_module: ?[]const u8 = null,
    owned_tx_build_function: ?[]const u8 = null,
    owned_tx_build_commands: ?[]const u8 = null,
    owned_tx_build_command_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_tx_build_type_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_tx_build_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_tx_build_sender: ?[]const u8 = null,
    owned_tx_build_type_args: ?[]const u8 = null,
    owned_tx_build_args: ?[]const u8 = null,
    owned_tx_build_gas_payment: ?[]const u8 = null,
    owned_tx_session_response: ?[]const u8 = null,
    owned_tx_provider_config: ?[]const u8 = null,
    owned_wallet_alias: ?[]const u8 = null,
    owned_wallet_private_key: ?[]const u8 = null,
    owned_intent_network: ?[]const u8 = null,
    owned_intent_execution_mode: ?[]const u8 = null,
    owned_intent_policy_json: ?[]const u8 = null,
    owned_request_sponsor_mode: ?[]const u8 = null,
    owned_request_sponsor_policy: ?[]const u8 = null,
    owned_request_correlation_id: ?[]const u8 = null,
    owned_request_entry_id: ?[]const u8 = null,
    owned_request_schedule_id: ?[]const u8 = null,
    owned_request_schedule_replace_id: ?[]const u8 = null,
    owned_account_objects_filter: ?[]const u8 = null,
    owned_account_objects_package: ?[]const u8 = null,
    owned_event_filter: ?[]const u8 = null,
    owned_event_package: ?[]const u8 = null,
    owned_event_module: ?[]const u8 = null,
    owned_event_type: ?[]const u8 = null,
    owned_event_sender: ?[]const u8 = null,
    owned_event_tx_digest_filter: ?[]const u8 = null,
    owned_event_cursor_tx_digest: ?[]const u8 = null,
    owned_move_package: ?[]const u8 = null,
    owned_move_module: ?[]const u8 = null,
    owned_move_function: ?[]const u8 = null,
    owned_object_id: ?[]const u8 = null,
    owned_object_parent_id: ?[]const u8 = null,
    owned_object_dynamic_field_name: ?[]const u8 = null,
    owned_object_dynamic_field_name_value: ?[]const u8 = null,
    owned_object_options: ?[]const u8 = null,
    signatures: std.ArrayListUnmanaged([]const u8) = .{},
    owned_signatures: std.ArrayListUnmanaged([]const u8) = .{},
    signers: std.ArrayListUnmanaged([]const u8) = .{},
    owned_signers: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.owned_rpc_url) |value| allocator.free(value);
        if (self.owned_params) |value| allocator.free(value);
        if (self.owned_tx_bytes) |value| allocator.free(value);
        if (self.owned_tx_options) |value| allocator.free(value);
        if (self.owned_tx_build_package) |value| allocator.free(value);
        if (self.owned_tx_build_module) |value| allocator.free(value);
        if (self.owned_tx_build_function) |value| allocator.free(value);
        if (self.owned_tx_build_commands) |value| allocator.free(value);
        for (self.owned_tx_build_command_items.items) |value| allocator.free(value);
        self.tx_build_command_items.deinit(allocator);
        self.owned_tx_build_command_items.deinit(allocator);
        for (self.owned_tx_build_type_arg_items.items) |value| allocator.free(value);
        self.tx_build_type_arg_items.deinit(allocator);
        self.owned_tx_build_type_arg_items.deinit(allocator);
        for (self.owned_tx_build_arg_items.items) |value| allocator.free(value);
        self.tx_build_arg_items.deinit(allocator);
        self.owned_tx_build_arg_items.deinit(allocator);
        if (self.owned_tx_build_sender) |value| allocator.free(value);
        if (self.owned_tx_build_type_args) |value| allocator.free(value);
        if (self.owned_tx_build_args) |value| allocator.free(value);
        if (self.owned_tx_build_gas_payment) |value| allocator.free(value);
        if (self.owned_tx_session_response) |value| allocator.free(value);
        if (self.owned_tx_provider_config) |value| allocator.free(value);
        if (self.owned_wallet_alias) |value| allocator.free(value);
        if (self.owned_wallet_private_key) |value| allocator.free(value);
        if (self.owned_intent_network) |value| allocator.free(value);
        if (self.owned_intent_execution_mode) |value| allocator.free(value);
        if (self.owned_intent_policy_json) |value| allocator.free(value);
        if (self.owned_request_sponsor_mode) |value| allocator.free(value);
        if (self.owned_request_sponsor_policy) |value| allocator.free(value);
        if (self.owned_request_correlation_id) |value| allocator.free(value);
        if (self.owned_request_entry_id) |value| allocator.free(value);
        if (self.owned_request_schedule_id) |value| allocator.free(value);
        if (self.owned_request_schedule_replace_id) |value| allocator.free(value);
        if (self.owned_account_objects_filter) |value| allocator.free(value);
        if (self.owned_account_objects_package) |value| allocator.free(value);
        if (self.owned_event_filter) |value| allocator.free(value);
        if (self.owned_event_package) |value| allocator.free(value);
        if (self.owned_event_module) |value| allocator.free(value);
        if (self.owned_event_type) |value| allocator.free(value);
        if (self.owned_event_sender) |value| allocator.free(value);
        if (self.owned_event_tx_digest_filter) |value| allocator.free(value);
        if (self.owned_event_cursor_tx_digest) |value| allocator.free(value);
        if (self.owned_move_package) |value| allocator.free(value);
        if (self.owned_move_module) |value| allocator.free(value);
        if (self.owned_move_function) |value| allocator.free(value);
        if (self.owned_move_function_indexed_args_json) |value| allocator.free(value);
        self.move_function_indexed_arg_indices.deinit(allocator);
        for (self.owned_move_function_indexed_arg_items.items) |value| allocator.free(value);
        self.move_function_indexed_arg_items.deinit(allocator);
        self.owned_move_function_indexed_arg_items.deinit(allocator);
        if (self.owned_move_function_indexed_object_args_json) |value| allocator.free(value);
        self.move_function_indexed_object_arg_indices.deinit(allocator);
        for (self.owned_move_function_indexed_object_arg_items.items) |value| allocator.free(value);
        self.move_function_indexed_object_arg_items.deinit(allocator);
        self.owned_move_function_indexed_object_arg_items.deinit(allocator);
        if (self.owned_object_id) |value| allocator.free(value);
        if (self.owned_object_parent_id) |value| allocator.free(value);
        if (self.owned_object_dynamic_field_name) |value| allocator.free(value);
        if (self.owned_object_dynamic_field_name_value) |value| allocator.free(value);
        if (self.owned_object_options) |value| allocator.free(value);
        for (self.owned_signatures.items) |value| allocator.free(value);
        self.signatures.deinit(allocator);
        self.owned_signatures.deinit(allocator);
        for (self.owned_signers.items) |value| allocator.free(value);
        self.signers.deinit(allocator);
        self.owned_signers.deinit(allocator);
    }
};

fn isRequestLifecycleCommand(command: Command) bool {
    return switch (command) {
        .wallet_intent_build,
        .wallet_intent_dry_run,
        .wallet_intent_send,
        .request_build,
        .request_inspect,
        .request_dry_run,
        .request_sponsor,
        .request_sign,
        .request_send,
        .request_schedule,
        .request_rebroadcast,
        => true,
        else => false,
    };
}

fn requestLifecycleConsumesRequestArtifact(command: Command) bool {
    return switch (command) {
        .wallet_intent_build,
        .wallet_intent_dry_run,
        .wallet_intent_send,
        .request_build,
        .request_inspect,
        .request_dry_run,
        .request_sponsor,
        .request_sign,
        .request_send,
        .request_schedule,
        => true,
        else => false,
    };
}

fn requestLifecycleUsesProviderFlow(command: Command) bool {
    return switch (command) {
        .wallet_intent_send, .request_sign, .request_send, .request_rebroadcast => true,
        else => false,
    };
}

fn isWalletIntentLifecycleCommand(command: Command) bool {
    return switch (command) {
        .wallet_intent_build,
        .wallet_intent_dry_run,
        .wallet_intent_send,
        => true,
        else => false,
    };
}

const LoadedArg = struct {
    value: []const u8,
    owned: bool,
};

const CommandAliasMap = tx_request_builder.CommandResultAliases;

fn parseIntValue(value: []const u8) !u64 {
    return std.fmt.parseInt(u64, value, 10);
}

fn parseMoveFunctionTemplateOutput(value: []const u8) !MoveFunctionTemplateOutput {
    if (std.mem.eql(u8, value, "commands")) return .commands;
    if (std.mem.eql(u8, value, "preferred-commands")) return .preferred_commands;
    if (std.mem.eql(u8, value, "dry-run-request")) return .tx_dry_run_request;
    if (std.mem.eql(u8, value, "preferred-dry-run-request")) return .preferred_tx_dry_run_request;
    if (std.mem.eql(u8, value, "send-request")) return .tx_send_from_keystore_request;
    if (std.mem.eql(u8, value, "preferred-send-request")) return .preferred_tx_send_from_keystore_request;
    return error.InvalidCli;
}

pub fn hasMoveCallArgs(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_package != null or
        parsed.tx_build_module != null or
        parsed.tx_build_function != null or
        parsed.tx_build_type_args != null or
        parsed.tx_build_args != null;
}

pub fn hasCompleteMoveCallArgs(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_package != null and
        parsed.tx_build_module != null and
        parsed.tx_build_function != null;
}

pub fn hasCommandItems(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_command_items.items.len > 0;
}

pub fn hasProgrammaticTxInput(parsed: *const ParsedArgs) bool {
    return parsed.tx_build_commands != null or
        hasCommandItems(parsed) or
        hasMoveCallArgs(parsed);
}

pub fn hasProgrammaticTxContext(parsed: *const ParsedArgs) bool {
    return hasProgrammaticTxInput(parsed) or
        parsed.tx_build_sender != null or
        parsed.tx_build_gas_budget != null or
        parsed.tx_build_gas_price != null or
        parsed.tx_build_gas_payment != null or
        parsed.tx_build_auto_gas_payment or
        parsed.tx_build_auto_gas_budget or
        parsed.tx_build_gas_payment_min_balance != null or
        parsed.tx_build_type_args != null or
        parsed.tx_build_args != null;
}

pub fn validateProgrammaticTxInput(parsed: *const ParsedArgs) !void {
    const has_commands = parsed.tx_build_commands != null or hasCommandItems(parsed);
    const has_partial_move_call = hasMoveCallArgs(parsed);

    if (has_commands) {
        if (has_partial_move_call) return error.InvalidCli;
        return;
    }
    if (!has_partial_move_call) return;

    if (parsed.tx_build_package == null or
        parsed.tx_build_module == null or
        parsed.tx_build_function == null)
    {
        return error.InvalidCli;
    }
}

pub fn supportsProgrammableInput(parsed: *const ParsedArgs) bool {
    if (parsed.tx_build_commands != null or hasCommandItems(parsed)) return true;
    return parsed.tx_build_package != null and
        parsed.tx_build_module != null and
        parsed.tx_build_function != null;
}

pub fn validateProgrammaticCommandEntry(entry: std.json.Value) !void {
    try tx_builder.validateCommandEntry(entry);
}

fn validateProgrammaticCommandsArg(allocator: std.mem.Allocator, raw: []const u8) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    defer if (loaded.owned) allocator.free(loaded.value);

    const trimmed = std.mem.trim(u8, loaded.value, " \n\r\t");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    switch (parsed.value) {
        .array => {
            if (parsed.value.array.items.len == 0) return error.InvalidCli;
            for (parsed.value.array.items) |entry| {
                try validateProgrammaticCommandEntry(entry);
            }
        },
        .object => try validateProgrammaticCommandEntry(parsed.value),
        else => return error.InvalidCli,
    }
}

fn maybeLoadFileValue(allocator: std.mem.Allocator, value: []const u8) !LoadedArg {
    if (value.len > 0 and value[0] == '@') {
        if (value.len == 1) return error.InvalidCli;
        if (std.mem.startsWith(u8, value, "@0x")) {
            for (value[3..]) |ch| {
                if (std.fmt.charToDigit(ch, 16) catch null == null) break else {}
            } else {
                return .{ .value = value, .owned = false };
            }
        }
        const path = value[1..];
        if (std.mem.eql(u8, path, "-")) {
            const owned_value = if (test_stdin_value_override) |override|
                try allocator.dupe(u8, override)
            else blk: {
                var file = std.fs.File.stdin();
                const loaded = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
                break :blk try trimOwnedLoadedValue(allocator, loaded);
            };
            return .{
                .value = owned_value,
                .owned = true,
            };
        }
        const loaded = if (std.fs.path.isAbsolute(path))
            try readAbsoluteFileAlloc(allocator, path)
        else
            try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
        const owned_value = try trimOwnedLoadedValue(allocator, loaded);
        return .{
            .value = owned_value,
            .owned = true,
        };
    }

    return .{ .value = value, .owned = false };
}

fn readAbsoluteFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

fn trimOwnedLoadedValue(allocator: std.mem.Allocator, loaded: []u8) ![]u8 {
    const trimmed = std.mem.trim(u8, loaded, " \n\r\t");
    if (trimmed.ptr == loaded.ptr and trimmed.len == loaded.len) return loaded;

    const owned_value = try allocator.dupe(u8, trimmed);
    allocator.free(loaded);
    return owned_value;
}

fn maybeLoadPackageValue(allocator: std.mem.Allocator, raw: []const u8) !LoadedArg {
    const loaded = try maybeLoadFileValue(allocator, raw);
    if (package_preset.resolvePackageIdAlias(loaded.value)) |resolved| {
        if (loaded.owned) allocator.free(loaded.value);
        return .{
            .value = try allocator.dupe(u8, resolved),
            .owned = true,
        };
    }
    return loaded;
}

fn maybeLoadObjectIdValue(allocator: std.mem.Allocator, raw: []const u8) !LoadedArg {
    const loaded = try maybeLoadFileValue(allocator, raw);
    if (object_preset.resolveObjectIdAlias(loaded.value)) |resolved| {
        if (loaded.owned) allocator.free(loaded.value);
        return .{
            .value = try allocator.dupe(u8, resolved),
            .owned = true,
        };
    }
    return loaded;
}

fn normalizeMoveFunctionObjectArgValueJson(
    allocator: std.mem.Allocator,
    raw: []const u8,
) ![]u8 {
    const loaded = try maybeLoadFileValue(allocator, raw);
    defer if (loaded.owned) allocator.free(loaded.value);

    const trimmed = std.mem.trim(u8, loaded.value, " \n\r\t");
    if (trimmed.len != 0 and (trimmed[0] == '[' or trimmed[0] == '"')) {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
        defer parsed.deinit();

        switch (parsed.value) {
            .string => |value| {
                const resolved = object_preset.resolveObjectIdAlias(value) orelse value;
                return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(resolved, .{})});
            },
            .array => |values| {
                var output = std.ArrayList(u8){};
                defer output.deinit(allocator);
                const writer = output.writer(allocator);
                try writer.writeAll("[");
                for (values.items, 0..) |item, index| {
                    if (item != .string) return error.InvalidCli;
                    const resolved = object_preset.resolveObjectIdAlias(item.string) orelse item.string;
                    if (index != 0) try writer.writeAll(",");
                    try writer.print("{f}", .{std.json.fmt(resolved, .{})});
                }
                try writer.writeAll("]");
                return try output.toOwnedSlice(allocator);
            },
            else => return error.InvalidCli,
        }
    }

    const resolved = object_preset.resolveObjectIdAlias(trimmed) orelse trimmed;
    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(resolved, .{})});
}

fn jsonObjectFieldAny(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) ?std.json.Value {
    inline for (names) |name| {
        if (object.get(name)) |value| return value;
    }
    return null;
}

fn replaceOwnedOptionalValue(
    allocator: std.mem.Allocator,
    owned_slot: *?[]const u8,
    value_slot: *?[]const u8,
    value: []u8,
) void {
    if (owned_slot.*) |old| allocator.free(old);
    owned_slot.* = value;
    value_slot.* = value;
}

fn appendOwnedRepeatedValue(
    allocator: std.mem.Allocator,
    items: *std.ArrayListUnmanaged([]const u8),
    owned_items: *std.ArrayListUnmanaged([]const u8),
    value: []const u8,
) !void {
    const owned = try allocator.dupe(u8, value);
    try items.append(allocator, owned);
    try owned_items.append(allocator, owned);
}

fn renderJsonValueCompact(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    var rendered = std.ArrayList(u8){};
    defer rendered.deinit(allocator);
    try rendered.writer(allocator).print("{f}", .{std.json.fmt(value, .{})});
    return try rendered.toOwnedSlice(allocator);
}

fn normalizeSingleArgumentValueToken(
    allocator: std.mem.Allocator,
    raw: []const u8,
) ![]u8 {
    if (tokenStartsSelectedRequest(raw)) {
        try validateSelectedRequestToken(allocator, raw);
        return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(raw, .{})});
    }

    const normalized_array_json = try tx_request_builder.buildArgumentValueTokenArray(
        allocator,
        null,
        &.{raw},
    );
    defer allocator.free(normalized_array_json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized_array_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array or parsed.value.array.items.len != 1) return error.InvalidCli;
    return try renderJsonValueCompact(allocator, parsed.value.array.items[0]);
}

fn buildMoveFunctionIndexedArgsJson(
    allocator: std.mem.Allocator,
    indices: []const usize,
    raw_values: []const []const u8,
) ![]u8 {
    if (indices.len != raw_values.len) return error.InvalidCli;

    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);
    try writer.writeAll("[");
    for (indices, raw_values, 0..) |index, raw_value, item_index| {
        const entry = try seen.getOrPut(index);
        if (entry.found_existing) return error.InvalidCli;
        const normalized_value = try normalizeSingleArgumentValueToken(allocator, raw_value);
        defer allocator.free(normalized_value);

        if (item_index != 0) try writer.writeAll(",");
        try writer.print(
            "{{\"index\":{},\"value\":{s}}}",
            .{ index, normalized_value },
        );
    }
    try writer.writeAll("]");
    return try output.toOwnedSlice(allocator);
}

fn buildMoveFunctionIndexedObjectArgsJson(
    allocator: std.mem.Allocator,
    indices: []const usize,
    raw_values: []const []const u8,
) ![]u8 {
    if (indices.len != raw_values.len) return error.InvalidCli;

    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);
    try writer.writeAll("[");
    for (indices, raw_values, 0..) |index, raw_value, item_index| {
        const entry = try seen.getOrPut(index);
        if (entry.found_existing) return error.InvalidCli;

        const normalized_value = try normalizeMoveFunctionObjectArgValueJson(allocator, raw_value);
        defer allocator.free(normalized_value);

        if (item_index != 0) try writer.writeAll(",");
        try writer.print(
            "{{\"index\":{},\"value\":{s}}}",
            .{ index, normalized_value },
        );
    }
    try writer.writeAll("]");
    return try output.toOwnedSlice(allocator);
}

fn parseOptionalRequestJsonBool(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?bool {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .bool => |flag| flag,
        else => error.InvalidCli,
    };
}

fn parseOptionalRequestJsonU64(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?u64 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .integer => |number| blk: {
            if (number < 0) return error.InvalidCli;
            break :blk @as(u64, @intCast(number));
        },
        .string => |text| try std.fmt.parseInt(u64, text, 10),
        else => error.InvalidCli,
    };
}

fn parseOptionalRequestJsonString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]u8 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCli,
    };
}

fn parseOptionalRequestJsonText(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]u8 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        .array, .object => try renderJsonValueCompact(allocator, value),
        else => return error.InvalidCli,
    };
}

fn validateProgrammaticCommandsJsonValue(value: std.json.Value) !void {
    switch (value) {
        .array => {
            if (value.array.items.len == 0) return error.InvalidCli;
            for (value.array.items) |entry| try validateProgrammaticCommandEntry(entry);
        },
        .object => try validateProgrammaticCommandEntry(value),
        else => return error.InvalidCli,
    }
}

fn appendRequestStringItems(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime singular_names: []const []const u8,
    comptime plural_names: []const []const u8,
    items: *std.ArrayListUnmanaged([]const u8),
    owned_items: *std.ArrayListUnmanaged([]const u8),
) !void {
    if (jsonObjectFieldAny(object, singular_names)) |value| {
        switch (value) {
            .null => {},
            .string => |text| try appendOwnedRepeatedValue(allocator, items, owned_items, text),
            else => return error.InvalidCli,
        }
    }

    if (jsonObjectFieldAny(object, plural_names)) |value| {
        switch (value) {
            .null => {},
            .array => {
                for (value.array.items) |entry| {
                    if (entry != .string) return error.InvalidCli;
                    try appendOwnedRepeatedValue(allocator, items, owned_items, entry.string);
                }
            },
            else => return error.InvalidCli,
        }
    }
}

pub fn applyProgrammaticRequestArtifact(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    raw: []const u8,
) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    defer if (loaded.owned) allocator.free(loaded.value);

    const request_json = std.mem.trim(u8, loaded.value, " \n\r\t");
    const request = try std.json.parseFromSlice(std.json.Value, allocator, request_json, .{});
    defer request.deinit();
    if (request.value != .object) return error.InvalidCli;

    if (jsonObjectFieldAny(request.value.object, &.{ "commands", "command" })) |commands_value| {
        try validateProgrammaticCommandsJsonValue(commands_value);
        const commands_json = try renderJsonValueCompact(allocator, commands_value);
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_tx_build_commands,
            &parsed.tx_build_commands,
            commands_json,
        );
    }

    if (try parseOptionalRequestJsonString(allocator, request.value.object, &.{"sender"})) |sender| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_tx_build_sender,
            &parsed.tx_build_sender,
            sender,
        );
    }
    if (try parseOptionalRequestJsonText(allocator, request.value.object, &.{ "gasPayment", "gas_payment", "gasPaymentJson", "gas_payment_json" })) |gas_payment| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_tx_build_gas_payment,
            &parsed.tx_build_gas_payment,
            gas_payment,
        );
    }
    if (try parseOptionalRequestJsonText(allocator, request.value.object, &.{ "options", "optionsJson", "options_json" })) |options_json| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_tx_options,
            &parsed.tx_options,
            options_json,
        );
    }
    if (try parseOptionalRequestJsonU64(request.value.object, &.{ "gasBudget", "gas_budget" })) |gas_budget| {
        parsed.tx_build_gas_budget = gas_budget;
    }
    if (try parseOptionalRequestJsonU64(request.value.object, &.{ "gasPrice", "gas_price" })) |gas_price| {
        parsed.tx_build_gas_price = gas_price;
    }
    if (try parseOptionalRequestJsonU64(request.value.object, &.{ "gasPaymentMinBalance", "gas_payment_min_balance" })) |min_balance| {
        parsed.tx_build_gas_payment_min_balance = min_balance;
    }
    if (try parseOptionalRequestJsonU64(request.value.object, &.{ "confirmTimeoutMs", "confirm_timeout_ms" })) |timeout_ms| {
        parsed.confirm_timeout_ms = timeout_ms;
    }
    if (try parseOptionalRequestJsonU64(request.value.object, &.{ "confirmPollMs", "confirm_poll_ms" })) |poll_ms| {
        parsed.confirm_poll_ms = poll_ms;
    }
    if (try parseOptionalRequestJsonBool(request.value.object, &.{ "fromKeystore", "from_keystore" })) |from_keystore| {
        parsed.from_keystore = from_keystore;
    }
    if (try parseOptionalRequestJsonBool(request.value.object, &.{ "autoGasPayment", "auto_gas_payment" })) |auto_gas| {
        parsed.tx_build_auto_gas_payment = auto_gas;
    }
    if (try parseOptionalRequestJsonBool(request.value.object, &.{ "autoGasBudget", "auto_gas_budget" })) |auto_gas_budget| {
        parsed.tx_build_auto_gas_budget = auto_gas_budget;
    }
    if (try parseOptionalRequestJsonBool(request.value.object, &.{ "wait", "waitForConfirmation", "wait_for_confirmation" })) |wait| {
        parsed.tx_send_wait = wait;
    }
    if (try parseOptionalRequestJsonBool(request.value.object, &.{ "summarize", "summary" })) |summarize| {
        parsed.tx_send_summarize = summarize;
    }
    if (try parseOptionalRequestJsonBool(request.value.object, &.{"observe"})) |observe| {
        parsed.tx_send_observe = observe;
    }

    try appendRequestStringItems(
        allocator,
        request.value.object,
        &.{"signer"},
        &.{"signers"},
        &parsed.signers,
        &parsed.owned_signers,
    );
    try appendRequestStringItems(
        allocator,
        request.value.object,
        &.{ "signature", "sig" },
        &.{"signatures"},
        &parsed.signatures,
        &parsed.owned_signatures,
    );
}

pub fn applyWalletIntentArtifact(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    raw: []const u8,
) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    defer if (loaded.owned) allocator.free(loaded.value);

    var envelope = try wallet_intent.parseEnvelope(allocator, std.mem.trim(u8, loaded.value, " \n\r\t"));
    defer envelope.deinit(allocator);

    try applyProgrammaticRequestArtifact(allocator, parsed, envelope.request_json);

    if (envelope.network) |value| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_intent_network,
            &parsed.intent_network,
            value,
        );
        envelope.network = null;
    }
    if (envelope.execution_mode) |value| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_intent_execution_mode,
            &parsed.intent_execution_mode,
            value,
        );
        envelope.execution_mode = null;
    }
    if (envelope.policy_json) |value| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_intent_policy_json,
            &parsed.intent_policy_json,
            value,
        );
        envelope.policy_json = null;
    }
    if (envelope.correlation_id) |value| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_request_correlation_id,
            &parsed.request_correlation_id,
            value,
        );
        envelope.correlation_id = null;
    }
    if (envelope.valid_after_ms) |value| parsed.request_valid_after_ms = value;
    if (envelope.valid_before_ms) |value| parsed.request_valid_before_ms = value;
    if (envelope.sponsor_mode) |value| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_request_sponsor_mode,
            &parsed.request_sponsor_mode,
            value,
        );
        envelope.sponsor_mode = null;
    }
    if (envelope.sponsor_policy_json) |value| {
        replaceOwnedOptionalValue(
            allocator,
            &parsed.owned_request_sponsor_policy,
            &parsed.request_sponsor_policy,
            value,
        );
        envelope.sponsor_policy_json = null;
    }
}

fn deinitCommandAliases(allocator: std.mem.Allocator, aliases: *CommandAliasMap) void {
    tx_request_builder.deinitCommandResultAliases(allocator, aliases);
}

fn assignCommandAlias(
    allocator: std.mem.Allocator,
    parsed: *const ParsedArgs,
    aliases: *CommandAliasMap,
    raw_name: []const u8,
) !void {
    if (parsed.tx_build_command_items.items.len == 0) return error.InvalidCli;
    try tx_request_builder.assignCommandResultAlias(
        allocator,
        aliases,
        raw_name,
        parsed.tx_build_command_items.items.len - 1,
    );
}

fn appendSignatureValue(allocator: std.mem.Allocator, parsed: *ParsedArgs, raw: []const u8) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    try parsed.signatures.append(allocator, loaded.value);
    if (loaded.owned) try parsed.owned_signatures.append(allocator, loaded.value);
}

fn appendSignatureFileValue(allocator: std.mem.Allocator, parsed: *ParsedArgs, path: []const u8) !void {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \n\r\t");
    const value = try allocator.dupe(u8, trimmed);
    try parsed.signatures.append(allocator, value);
    try parsed.owned_signatures.append(allocator, value);
}

fn appendSignerValue(allocator: std.mem.Allocator, parsed: *ParsedArgs, raw: []const u8) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    try parsed.signers.append(allocator, loaded.value);
    if (loaded.owned) try parsed.owned_signers.append(allocator, loaded.value);
}

fn appendCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    aliases: *const CommandAliasMap,
    raw: []const u8,
) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    defer if (loaded.owned) allocator.free(loaded.value);

    var normalized = try tx_request_builder.normalizeCommandItemsFromRawJsonWithContext(
        allocator,
        aliases,
        parsed.tx_build_command_items.items.len,
        loaded.value,
    );
    errdefer normalized.deinit(allocator);
    try normalized.appendToOwnedLists(
        allocator,
        &parsed.tx_build_command_items,
        &parsed.owned_tx_build_command_items,
    );
}

fn appendBuiltCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    command_json: []u8,
) !void {
    try parsed.tx_build_command_items.append(allocator, command_json);
    try parsed.owned_tx_build_command_items.append(allocator, command_json);
}

fn initDslCommandBuilder(
    allocator: std.mem.Allocator,
    aliases: *const CommandAliasMap,
) !tx_request_builder.ProgrammaticDslBuilder {
    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    errdefer builder.deinit();
    try builder.importAliases(aliases);
    return builder;
}

fn finishDslCommandValue(
    allocator: std.mem.Allocator,
    builder: *tx_request_builder.ProgrammaticDslBuilder,
) ![]u8 {
    var owned = try builder.finish();
    defer owned.deinit(allocator);
    return owned.takeCommandsJson() orelse error.InvalidCli;
}

fn appendRepeatedLoadedValue(
    allocator: std.mem.Allocator,
    items: *std.ArrayListUnmanaged([]const u8),
    owned_items: *std.ArrayListUnmanaged([]const u8),
    raw: []const u8,
) !void {
    const loaded = try maybeLoadFileValue(allocator, raw);
    try items.append(allocator, loaded.value);
    if (loaded.owned) try owned_items.append(allocator, loaded.value);
}

fn appendIndexedRepeatedLoadedValue(
    allocator: std.mem.Allocator,
    indices: *std.ArrayListUnmanaged(usize),
    items: *std.ArrayListUnmanaged([]const u8),
    owned_items: *std.ArrayListUnmanaged([]const u8),
    index_raw: []const u8,
    raw: []const u8,
) !void {
    const parsed_index = try parseIntValue(index_raw);
    if (parsed_index > std.math.maxInt(usize)) return error.InvalidCli;

    const loaded = try maybeLoadFileValue(allocator, raw);
    errdefer if (loaded.owned) allocator.free(loaded.value);

    try indices.append(allocator, @as(usize, @intCast(parsed_index)));
    errdefer _ = indices.pop();
    try items.append(allocator, loaded.value);
    errdefer _ = items.pop();
    if (loaded.owned) try owned_items.append(allocator, loaded.value);
}

fn appendIndexedRepeatedLoadedObjectIdValue(
    allocator: std.mem.Allocator,
    indices: *std.ArrayListUnmanaged(usize),
    items: *std.ArrayListUnmanaged([]const u8),
    owned_items: *std.ArrayListUnmanaged([]const u8),
    index_raw: []const u8,
    raw: []const u8,
) !void {
    const parsed_index = try parseIntValue(index_raw);
    if (parsed_index > std.math.maxInt(usize)) return error.InvalidCli;

    const loaded = try maybeLoadObjectIdValue(allocator, raw);
    errdefer if (loaded.owned) allocator.free(loaded.value);

    try indices.append(allocator, @as(usize, @intCast(parsed_index)));
    errdefer _ = indices.pop();
    try items.append(allocator, loaded.value);
    errdefer _ = items.pop();
    if (loaded.owned) try owned_items.append(allocator, loaded.value);
}

const OwnedCliItems = struct {
    items: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *OwnedCliItems, allocator: std.mem.Allocator) void {
        for (self.items.items) |value| allocator.free(value);
        self.items.deinit(allocator);
    }
};

fn parseJsonArrayToCliItems(
    allocator: std.mem.Allocator,
    raw: []const u8,
) !OwnedCliItems {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;

    var out = OwnedCliItems{};
    errdefer out.deinit(allocator);

    for (parsed.value.array.items) |item| {
        if (item == .string) {
            try out.items.append(allocator, try allocator.dupe(u8, item.string));
            continue;
        }

        var rendered = std.ArrayList(u8){};
        errdefer rendered.deinit(allocator);
        try rendered.writer(allocator).print("{f}", .{std.json.fmt(item, .{})});
        try out.items.append(allocator, try rendered.toOwnedSlice(allocator));
    }

    return out;
}

fn parseNormalizedArgumentValueJsonArrayToCliItems(
    allocator: std.mem.Allocator,
    aliases: *const CommandAliasMap,
    raw: []const u8,
) !OwnedCliItems {
    if (try moveCallArgsContainSelectedRequestTokens(allocator, raw)) {
        return try parseJsonArrayToCliItems(allocator, std.mem.trim(u8, raw, " \n\r\t"));
    }
    const normalized = try tx_request_builder.normalizeArgumentValueJsonArray(allocator, aliases, raw);
    defer allocator.free(normalized);
    return try parseJsonArrayToCliItems(allocator, normalized);
}

fn appendTypedCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    aliases: *const CommandAliasMap,
    token: []const u8,
    first_raw: []const u8,
    second_raw: []const u8,
) !void {
    const first = try maybeLoadFileValue(allocator, first_raw);
    defer if (first.owned) allocator.free(first.value);

    const second = try maybeLoadFileValue(allocator, second_raw);
    defer if (second.owned) allocator.free(second.value);

    var builder = try initDslCommandBuilder(allocator, aliases);
    defer builder.deinit();

    if (std.mem.eql(u8, token, "--transfer-objects")) {
        var objects = try parseNormalizedArgumentValueJsonArrayToCliItems(allocator, aliases, first.value);
        defer objects.deinit(allocator);
        if (try moveCallArgItemsContainSelectedRequestTokens(allocator, objects.items.items) or tokenStartsSelectedRequest(second.value)) {
            if (tokenStartsSelectedRequest(second.value)) try validateSelectedRequestToken(allocator, second.value);
            const objects_json = try tx_builder.buildJsonStringArray(allocator, objects.items.items);
            defer allocator.free(objects_json);
            const command_json = try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"TransferObjects\",\"objects\":{s},\"address\":{f}}}]",
                .{ objects_json, std.json.fmt(second.value, .{}) },
            );
            try appendBuiltCommandValue(allocator, parsed, command_json);
            return;
        }
        try builder.appendTransferObjectsFromValueTokens(objects.items.items, second.value);
    } else if (std.mem.eql(u8, token, "--split-coins")) {
        var amounts = try parseNormalizedArgumentValueJsonArrayToCliItems(allocator, aliases, second.value);
        defer amounts.deinit(allocator);
        if (tokenStartsSelectedRequest(first.value) or try moveCallArgItemsContainSelectedRequestTokens(allocator, amounts.items.items)) {
            if (tokenStartsSelectedRequest(first.value)) try validateSelectedRequestToken(allocator, first.value);
            const amounts_json = try tx_builder.buildJsonStringArray(allocator, amounts.items.items);
            defer allocator.free(amounts_json);
            const command_json = try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"SplitCoins\",\"coin\":{f},\"amounts\":{s}}}]",
                .{ std.json.fmt(first.value, .{}), amounts_json },
            );
            try appendBuiltCommandValue(allocator, parsed, command_json);
            return;
        }
        try builder.appendSplitCoinsFromValueTokens(first.value, amounts.items.items);
    } else if (std.mem.eql(u8, token, "--merge-coins")) {
        var sources = try parseNormalizedArgumentValueJsonArrayToCliItems(allocator, aliases, second.value);
        defer sources.deinit(allocator);
        if (tokenStartsSelectedRequest(first.value) or try moveCallArgItemsContainSelectedRequestTokens(allocator, sources.items.items)) {
            if (tokenStartsSelectedRequest(first.value)) try validateSelectedRequestToken(allocator, first.value);
            const sources_json = try tx_builder.buildJsonStringArray(allocator, sources.items.items);
            defer allocator.free(sources_json);
            const command_json = try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"MergeCoins\",\"destination\":{f},\"sources\":{s}}}]",
                .{ std.json.fmt(first.value, .{}), sources_json },
            );
            try appendBuiltCommandValue(allocator, parsed, command_json);
            return;
        }
        try builder.appendMergeCoinsFromValueTokens(first.value, sources.items.items);
    } else {
        return error.InvalidCli;
    }

    const command_json = try finishDslCommandValue(allocator, &builder);
    try appendBuiltCommandValue(allocator, parsed, command_json);
}

fn appendTypedMoveCallCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    aliases: *const CommandAliasMap,
    package_raw: []const u8,
    module_raw: []const u8,
    function_raw: []const u8,
    type_args_raw: []const u8,
    args_raw: []const u8,
) !void {
    const package = try maybeLoadPackageValue(allocator, package_raw);
    defer if (package.owned) allocator.free(package.value);

    const module = try maybeLoadFileValue(allocator, module_raw);
    defer if (module.owned) allocator.free(module.value);

    const function_name = try maybeLoadFileValue(allocator, function_raw);
    defer if (function_name.owned) allocator.free(function_name.value);

    const type_args = try maybeLoadFileValue(allocator, type_args_raw);
    defer if (type_args.owned) allocator.free(type_args.value);

    const call_args = try maybeLoadFileValue(allocator, args_raw);
    defer if (call_args.owned) allocator.free(call_args.value);
    var builder = try initDslCommandBuilder(allocator, aliases);
    defer builder.deinit();

    const parsed_type_args = try std.json.parseFromSlice(std.json.Value, allocator, type_args.value, .{});
    defer parsed_type_args.deinit();
    if (parsed_type_args.value != .array) return error.InvalidCli;

    var type_arg_items = OwnedCliItems{};
    defer type_arg_items.deinit(allocator);
    for (parsed_type_args.value.array.items) |item| {
        if (item != .string) return error.InvalidCli;
        try type_arg_items.items.append(allocator, try allocator.dupe(u8, item.string));
    }

    var arg_items = try parseNormalizedArgumentValueJsonArrayToCliItems(allocator, aliases, call_args.value);
    defer arg_items.deinit(allocator);

    if (try moveCallArgItemsContainSelectedRequestTokens(allocator, arg_items.items.items)) {
        const type_args_json = try tx_builder.buildJsonStringArray(allocator, type_arg_items.items.items);
        defer allocator.free(type_args_json);
        const arguments_json = try tx_builder.buildJsonStringArray(allocator, arg_items.items.items);
        defer allocator.free(arguments_json);
        const command_json = try std.fmt.allocPrint(
            allocator,
            "[{{\"kind\":\"MoveCall\",\"package\":{f},\"module\":{f},\"function\":{f},\"typeArguments\":{s},\"arguments\":{s}}}]",
            .{
                std.json.fmt(package.value, .{}),
                std.json.fmt(module.value, .{}),
                std.json.fmt(function_name.value, .{}),
                type_args_json,
                arguments_json,
            },
        );
        try appendBuiltCommandValue(allocator, parsed, command_json);
        return;
    }

    try builder.appendMoveCallFromValueTokens(
        package.value,
        module.value,
        function_name.value,
        type_arg_items.items.items,
        arg_items.items.items,
    );

    const command_json = try finishDslCommandValue(allocator, &builder);
    try appendBuiltCommandValue(allocator, parsed, command_json);
}

fn appendTypedMakeMoveVecCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    aliases: *const CommandAliasMap,
    type_raw: []const u8,
    elements_raw: []const u8,
) !void {
    const type_value = try maybeLoadFileValue(allocator, type_raw);
    defer if (type_value.owned) allocator.free(type_value.value);

    const elements_value = try maybeLoadFileValue(allocator, elements_raw);
    defer if (elements_value.owned) allocator.free(elements_value.value);
    var builder = try initDslCommandBuilder(allocator, aliases);
    defer builder.deinit();

    var element_items = try parseNormalizedArgumentValueJsonArrayToCliItems(allocator, aliases, elements_value.value);
    defer element_items.deinit(allocator);

    if (try moveCallArgItemsContainSelectedRequestTokens(allocator, element_items.items.items)) {
        const elements_json = try tx_builder.buildJsonStringArray(allocator, element_items.items.items);
        defer allocator.free(elements_json);
        const command_json = if (std.mem.eql(u8, type_value.value, "null"))
            try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"MakeMoveVec\",\"type\":null,\"elements\":{s}}}]",
                .{elements_json},
            )
        else
            try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"MakeMoveVec\",\"type\":{f},\"elements\":{s}}}]",
                .{ std.json.fmt(type_value.value, .{}), elements_json },
            );
        try appendBuiltCommandValue(allocator, parsed, command_json);
        return;
    }

    try builder.appendMakeMoveVecFromValueTokens(type_value.value, element_items.items.items);

    const command_json = try finishDslCommandValue(allocator, &builder);
    try appendBuiltCommandValue(allocator, parsed, command_json);
}

fn appendTypedPublishCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    modules_raw: []const u8,
    dependencies_raw: []const u8,
) !void {
    const modules = try maybeLoadFileValue(allocator, modules_raw);
    defer if (modules.owned) allocator.free(modules.value);

    const dependencies = try maybeLoadFileValue(allocator, dependencies_raw);
    defer if (dependencies.owned) allocator.free(dependencies.value);

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendPublishFromCliValues(modules.value, dependencies.value);

    const command_json = try finishDslCommandValue(allocator, &builder);
    try appendBuiltCommandValue(allocator, parsed, command_json);
}

fn appendTypedUpgradeCommandValue(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    aliases: *const CommandAliasMap,
    modules_raw: []const u8,
    dependencies_raw: []const u8,
    package_raw: []const u8,
    ticket_raw: []const u8,
) !void {
    const modules = try maybeLoadFileValue(allocator, modules_raw);
    defer if (modules.owned) allocator.free(modules.value);

    const dependencies = try maybeLoadFileValue(allocator, dependencies_raw);
    defer if (dependencies.owned) allocator.free(dependencies.value);

    const package_id = try maybeLoadPackageValue(allocator, package_raw);
    defer if (package_id.owned) allocator.free(package_id.value);

    const ticket = try maybeLoadFileValue(allocator, ticket_raw);
    defer if (ticket.owned) allocator.free(ticket.value);

    var builder = try initDslCommandBuilder(allocator, aliases);
    defer builder.deinit();

    if (tokenStartsSelectedRequest(ticket.value)) {
        try validateSelectedRequestToken(allocator, ticket.value);
        const command_json = try std.fmt.allocPrint(
            allocator,
            "[{{\"kind\":\"Upgrade\",\"modules\":{s},\"dependencies\":{s},\"package\":{f},\"ticket\":{f}}}]",
            .{
                modules.value,
                dependencies.value,
                std.json.fmt(package_id.value, .{}),
                std.json.fmt(ticket.value, .{}),
            },
        );
        try appendBuiltCommandValue(allocator, parsed, command_json);
        return;
    }

    try builder.appendUpgradeFromValueToken(
        modules.value,
        dependencies.value,
        package_id.value,
        ticket.value,
    );

    const command_json = try finishDslCommandValue(allocator, &builder);
    try appendBuiltCommandValue(allocator, parsed, command_json);
}

const PendingTypedMoveCall = struct {
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    owned_package_id: ?[]const u8 = null,
    owned_module: ?[]const u8 = null,
    owned_function_name: ?[]const u8 = null,
    type_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_type_arg_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_arg_items: std.ArrayListUnmanaged([]const u8) = .{},

    fn init(
        allocator: std.mem.Allocator,
        package_raw: []const u8,
        module_raw: []const u8,
        function_raw: []const u8,
    ) !PendingTypedMoveCall {
        const package = try maybeLoadPackageValue(allocator, package_raw);
        errdefer if (package.owned) allocator.free(package.value);

        const module = try maybeLoadFileValue(allocator, module_raw);
        errdefer if (module.owned) allocator.free(module.value);

        const function_name = try maybeLoadFileValue(allocator, function_raw);
        errdefer if (function_name.owned) allocator.free(function_name.value);

        return .{
            .package_id = package.value,
            .module = module.value,
            .function_name = function_name.value,
            .owned_package_id = if (package.owned) package.value else null,
            .owned_module = if (module.owned) module.value else null,
            .owned_function_name = if (function_name.owned) function_name.value else null,
        };
    }

    fn deinit(self: *PendingTypedMoveCall, allocator: std.mem.Allocator) void {
        if (self.owned_package_id) |value| allocator.free(value);
        if (self.owned_module) |value| allocator.free(value);
        if (self.owned_function_name) |value| allocator.free(value);
        for (self.owned_type_arg_items.items) |value| allocator.free(value);
        self.type_arg_items.deinit(allocator);
        self.owned_type_arg_items.deinit(allocator);
        for (self.owned_arg_items.items) |value| allocator.free(value);
        self.arg_items.deinit(allocator);
        self.owned_arg_items.deinit(allocator);
    }

    fn appendTypeArg(self: *PendingTypedMoveCall, allocator: std.mem.Allocator, raw: []const u8) !void {
        try appendRepeatedLoadedValue(allocator, &self.type_arg_items, &self.owned_type_arg_items, raw);
    }

    fn appendArg(self: *PendingTypedMoveCall, allocator: std.mem.Allocator, raw: []const u8) !void {
        try appendRepeatedLoadedValue(allocator, &self.arg_items, &self.owned_arg_items, raw);
    }

    fn buildCommandJson(self: *PendingTypedMoveCall, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        if (try moveCallArgItemsContainSelectedRequestTokens(allocator, self.arg_items.items)) {
            const type_args_json = try tx_builder.buildJsonStringArray(allocator, self.type_arg_items.items);
            defer allocator.free(type_args_json);
            const arguments_json = try tx_builder.buildJsonStringArray(allocator, self.arg_items.items);
            defer allocator.free(arguments_json);
            return try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"MoveCall\",\"package\":{f},\"module\":{f},\"function\":{f},\"typeArguments\":{s},\"arguments\":{s}}}]",
                .{
                    std.json.fmt(self.package_id, .{}),
                    std.json.fmt(self.module, .{}),
                    std.json.fmt(self.function_name, .{}),
                    type_args_json,
                    arguments_json,
                },
            );
        }
        var builder = try initDslCommandBuilder(allocator, aliases);
        defer builder.deinit();
        try builder.appendMoveCallFromValueTokens(
            self.package_id,
            self.module,
            self.function_name,
            self.type_arg_items.items,
            self.arg_items.items,
        );
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedPublish = struct {
    modules: ?[]const u8 = null,
    owned_modules: ?[]const u8 = null,
    dependencies: ?[]const u8 = null,
    owned_dependencies: ?[]const u8 = null,

    fn deinit(self: *PendingTypedPublish, allocator: std.mem.Allocator) void {
        if (self.owned_modules) |value| allocator.free(value);
        if (self.owned_dependencies) |value| allocator.free(value);
    }

    fn setModules(self: *PendingTypedPublish, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_modules) |value| allocator.free(value);
        self.owned_modules = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_modules = loaded.value;
        self.modules = loaded.value;
    }

    fn setDependencies(self: *PendingTypedPublish, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_dependencies) |value| allocator.free(value);
        self.owned_dependencies = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_dependencies = loaded.value;
        self.dependencies = loaded.value;
    }

    fn buildCommandJson(self: *PendingTypedPublish, allocator: std.mem.Allocator) ![]u8 {
        const modules = self.modules orelse return error.InvalidCli;
        const dependencies = self.dependencies orelse return error.InvalidCli;

        var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
        defer builder.deinit();
        try builder.appendPublishFromCliValues(modules, dependencies);
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedTransferObjects = struct {
    object_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_object_items: std.ArrayListUnmanaged([]const u8) = .{},
    address: ?[]const u8 = null,
    owned_address: ?[]const u8 = null,

    fn deinit(self: *PendingTypedTransferObjects, allocator: std.mem.Allocator) void {
        for (self.owned_object_items.items) |value| allocator.free(value);
        self.object_items.deinit(allocator);
        self.owned_object_items.deinit(allocator);
        if (self.owned_address) |value| allocator.free(value);
    }

    fn appendObject(self: *PendingTypedTransferObjects, allocator: std.mem.Allocator, raw: []const u8) !void {
        try appendRepeatedLoadedValue(allocator, &self.object_items, &self.owned_object_items, raw);
    }

    fn setAddress(self: *PendingTypedTransferObjects, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_address) |value| allocator.free(value);
        self.owned_address = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_address = loaded.value;
        self.address = loaded.value;
    }

    fn buildCommandJson(self: *PendingTypedTransferObjects, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        const address = self.address orelse return error.InvalidCli;
        if (try moveCallArgItemsContainSelectedRequestTokens(allocator, self.object_items.items) or tokenStartsSelectedRequest(address)) {
            if (tokenStartsSelectedRequest(address)) try validateSelectedRequestToken(allocator, address);
            const objects_json = try tx_builder.buildJsonStringArray(allocator, self.object_items.items);
            defer allocator.free(objects_json);
            return try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"TransferObjects\",\"objects\":{s},\"address\":{f}}}]",
                .{ objects_json, std.json.fmt(address, .{}) },
            );
        }
        var builder = try initDslCommandBuilder(allocator, aliases);
        defer builder.deinit();
        try builder.appendTransferObjectsFromValueTokens(self.object_items.items, address);
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedSplitCoins = struct {
    coin: ?[]const u8 = null,
    owned_coin: ?[]const u8 = null,
    amount_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_amount_items: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *PendingTypedSplitCoins, allocator: std.mem.Allocator) void {
        if (self.owned_coin) |value| allocator.free(value);
        for (self.owned_amount_items.items) |value| allocator.free(value);
        self.amount_items.deinit(allocator);
        self.owned_amount_items.deinit(allocator);
    }

    fn setCoin(self: *PendingTypedSplitCoins, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_coin) |value| allocator.free(value);
        self.owned_coin = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_coin = loaded.value;
        self.coin = loaded.value;
    }

    fn appendAmount(self: *PendingTypedSplitCoins, allocator: std.mem.Allocator, raw: []const u8) !void {
        try appendRepeatedLoadedValue(allocator, &self.amount_items, &self.owned_amount_items, raw);
    }

    fn buildCommandJson(self: *PendingTypedSplitCoins, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        const coin = self.coin orelse return error.InvalidCli;
        if (tokenStartsSelectedRequest(coin) or try moveCallArgItemsContainSelectedRequestTokens(allocator, self.amount_items.items)) {
            if (tokenStartsSelectedRequest(coin)) try validateSelectedRequestToken(allocator, coin);
            const amounts_json = try tx_builder.buildJsonStringArray(allocator, self.amount_items.items);
            defer allocator.free(amounts_json);
            return try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"SplitCoins\",\"coin\":{f},\"amounts\":{s}}}]",
                .{ std.json.fmt(coin, .{}), amounts_json },
            );
        }
        var builder = try initDslCommandBuilder(allocator, aliases);
        defer builder.deinit();
        try builder.appendSplitCoinsFromValueTokens(coin, self.amount_items.items);
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedUpgrade = struct {
    modules: ?[]const u8 = null,
    owned_modules: ?[]const u8 = null,
    dependencies: ?[]const u8 = null,
    owned_dependencies: ?[]const u8 = null,
    package_id: ?[]const u8 = null,
    owned_package_id: ?[]const u8 = null,
    ticket: ?[]const u8 = null,
    owned_ticket: ?[]const u8 = null,

    fn deinit(self: *PendingTypedUpgrade, allocator: std.mem.Allocator) void {
        if (self.owned_modules) |value| allocator.free(value);
        if (self.owned_dependencies) |value| allocator.free(value);
        if (self.owned_package_id) |value| allocator.free(value);
        if (self.owned_ticket) |value| allocator.free(value);
    }

    fn setModules(self: *PendingTypedUpgrade, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_modules) |value| allocator.free(value);
        self.owned_modules = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_modules = loaded.value;
        self.modules = loaded.value;
    }

    fn setDependencies(self: *PendingTypedUpgrade, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_dependencies) |value| allocator.free(value);
        self.owned_dependencies = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_dependencies = loaded.value;
        self.dependencies = loaded.value;
    }

    fn setPackage(self: *PendingTypedUpgrade, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_package_id) |value| allocator.free(value);
        self.owned_package_id = null;

        const loaded = try maybeLoadPackageValue(allocator, raw);
        if (loaded.owned) self.owned_package_id = loaded.value;
        self.package_id = loaded.value;
    }

    fn setTicket(self: *PendingTypedUpgrade, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_ticket) |value| allocator.free(value);
        self.owned_ticket = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_ticket = loaded.value;
        self.ticket = loaded.value;
    }

    fn buildCommandJson(self: *PendingTypedUpgrade, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        const modules = self.modules orelse return error.InvalidCli;
        const dependencies = self.dependencies orelse return error.InvalidCli;
        const package_id = self.package_id orelse return error.InvalidCli;
        const ticket = self.ticket orelse return error.InvalidCli;

        if (tokenStartsSelectedRequest(ticket)) {
            try validateSelectedRequestToken(allocator, ticket);
            return try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"Upgrade\",\"modules\":{s},\"dependencies\":{s},\"package\":{f},\"ticket\":{f}}}]",
                .{
                    modules,
                    dependencies,
                    std.json.fmt(package_id, .{}),
                    std.json.fmt(ticket, .{}),
                },
            );
        }

        var builder = try initDslCommandBuilder(allocator, aliases);
        defer builder.deinit();
        try builder.appendUpgradeFromValueToken(modules, dependencies, package_id, ticket);
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedMergeCoins = struct {
    destination: ?[]const u8 = null,
    owned_destination: ?[]const u8 = null,
    source_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_source_items: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *PendingTypedMergeCoins, allocator: std.mem.Allocator) void {
        if (self.owned_destination) |value| allocator.free(value);
        for (self.owned_source_items.items) |value| allocator.free(value);
        self.source_items.deinit(allocator);
        self.owned_source_items.deinit(allocator);
    }

    fn setDestination(self: *PendingTypedMergeCoins, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_destination) |value| allocator.free(value);
        self.owned_destination = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_destination = loaded.value;
        self.destination = loaded.value;
    }

    fn appendSource(self: *PendingTypedMergeCoins, allocator: std.mem.Allocator, raw: []const u8) !void {
        try appendRepeatedLoadedValue(allocator, &self.source_items, &self.owned_source_items, raw);
    }

    fn buildCommandJson(self: *PendingTypedMergeCoins, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        const destination = self.destination orelse return error.InvalidCli;
        if (tokenStartsSelectedRequest(destination) or try moveCallArgItemsContainSelectedRequestTokens(allocator, self.source_items.items)) {
            if (tokenStartsSelectedRequest(destination)) try validateSelectedRequestToken(allocator, destination);
            const sources_json = try tx_builder.buildJsonStringArray(allocator, self.source_items.items);
            defer allocator.free(sources_json);
            return try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"MergeCoins\",\"destination\":{f},\"sources\":{s}}}]",
                .{ std.json.fmt(destination, .{}), sources_json },
            );
        }
        var builder = try initDslCommandBuilder(allocator, aliases);
        defer builder.deinit();
        try builder.appendMergeCoinsFromValueTokens(destination, self.source_items.items);
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedMakeMoveVec = struct {
    type_value: ?[]const u8 = null,
    owned_type_value: ?[]const u8 = null,
    element_items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_element_items: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *PendingTypedMakeMoveVec, allocator: std.mem.Allocator) void {
        if (self.owned_type_value) |value| allocator.free(value);
        for (self.owned_element_items.items) |value| allocator.free(value);
        self.element_items.deinit(allocator);
        self.owned_element_items.deinit(allocator);
    }

    fn setType(self: *PendingTypedMakeMoveVec, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.owned_type_value) |value| allocator.free(value);
        self.owned_type_value = null;

        const loaded = try maybeLoadFileValue(allocator, raw);
        if (loaded.owned) self.owned_type_value = loaded.value;
        self.type_value = loaded.value;
    }

    fn appendElement(self: *PendingTypedMakeMoveVec, allocator: std.mem.Allocator, raw: []const u8) !void {
        try appendRepeatedLoadedValue(allocator, &self.element_items, &self.owned_element_items, raw);
    }

    fn buildCommandJson(self: *PendingTypedMakeMoveVec, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        if (try moveCallArgItemsContainSelectedRequestTokens(allocator, self.element_items.items)) {
            const elements_json = try tx_builder.buildJsonStringArray(allocator, self.element_items.items);
            defer allocator.free(elements_json);
            if (self.type_value) |type_value| {
                return try std.fmt.allocPrint(
                    allocator,
                    "[{{\"kind\":\"MakeMoveVec\",\"type\":{f},\"elements\":{s}}}]",
                    .{ std.json.fmt(type_value, .{}), elements_json },
                );
            }
            return try std.fmt.allocPrint(
                allocator,
                "[{{\"kind\":\"MakeMoveVec\",\"type\":null,\"elements\":{s}}}]",
                .{elements_json},
            );
        }
        var builder = try initDslCommandBuilder(allocator, aliases);
        defer builder.deinit();
        try builder.appendMakeMoveVecFromValueTokens(self.type_value, self.element_items.items);
        return try finishDslCommandValue(allocator, &builder);
    }
};

const PendingTypedCommand = union(enum) {
    move_call: PendingTypedMoveCall,
    publish: PendingTypedPublish,
    transfer_objects: PendingTypedTransferObjects,
    upgrade: PendingTypedUpgrade,
    split_coins: PendingTypedSplitCoins,
    merge_coins: PendingTypedMergeCoins,
    make_move_vec: PendingTypedMakeMoveVec,

    fn deinit(self: *PendingTypedCommand, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_call => |*pending| pending.deinit(allocator),
            .publish => |*pending| pending.deinit(allocator),
            .transfer_objects => |*pending| pending.deinit(allocator),
            .upgrade => |*pending| pending.deinit(allocator),
            .split_coins => |*pending| pending.deinit(allocator),
            .merge_coins => |*pending| pending.deinit(allocator),
            .make_move_vec => |*pending| pending.deinit(allocator),
        }
    }

    fn buildCommandJson(self: *PendingTypedCommand, allocator: std.mem.Allocator, aliases: *const CommandAliasMap) ![]u8 {
        return switch (self.*) {
            .move_call => |*pending| pending.buildCommandJson(allocator, aliases),
            .publish => |*pending| pending.buildCommandJson(allocator),
            .transfer_objects => |*pending| pending.buildCommandJson(allocator, aliases),
            .upgrade => |*pending| pending.buildCommandJson(allocator, aliases),
            .split_coins => |*pending| pending.buildCommandJson(allocator, aliases),
            .merge_coins => |*pending| pending.buildCommandJson(allocator, aliases),
            .make_move_vec => |*pending| pending.buildCommandJson(allocator, aliases),
        };
    }

    fn acceptsFragment(self: *const PendingTypedCommand, token: []const u8) bool {
        return switch (self.*) {
            .move_call => std.mem.eql(u8, token, "--move-call-type-arg") or std.mem.eql(u8, token, "--move-call-arg"),
            .publish => std.mem.eql(u8, token, "--publish-modules") or std.mem.eql(u8, token, "--publish-dependencies"),
            .transfer_objects => std.mem.eql(u8, token, "--transfer-object") or std.mem.eql(u8, token, "--transfer-address"),
            .upgrade => std.mem.eql(u8, token, "--upgrade-modules") or std.mem.eql(u8, token, "--upgrade-dependencies") or std.mem.eql(u8, token, "--upgrade-package") or std.mem.eql(u8, token, "--upgrade-ticket"),
            .split_coins => std.mem.eql(u8, token, "--split-coin") or std.mem.eql(u8, token, "--split-amount"),
            .merge_coins => std.mem.eql(u8, token, "--merge-destination") or std.mem.eql(u8, token, "--merge-source"),
            .make_move_vec => std.mem.eql(u8, token, "--make-move-vec-type") or std.mem.eql(u8, token, "--make-move-vec-element"),
        };
    }
};

fn flushPendingTypedCommand(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    pending_command: *?PendingTypedCommand,
    aliases: *const CommandAliasMap,
) !void {
    if (pending_command.*) |*pending| {
        const command_json = try pending.buildCommandJson(allocator, aliases);
        pending.deinit(allocator);
        pending_command.* = null;
        try appendBuiltCommandValue(allocator, parsed, command_json);
    }
}

fn maybeFlushPendingTypedCommand(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    pending_command: *?PendingTypedCommand,
    aliases: *const CommandAliasMap,
    token: []const u8,
) !void {
    if (pending_command.*) |*pending| {
        if (pending.acceptsFragment(token)) return;
    } else {
        return;
    }
    try flushPendingTypedCommand(allocator, parsed, pending_command, aliases);
}

fn tryParseTypedCommandOption(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    args: []const []const u8,
    index: *usize,
    pending_command: *?PendingTypedCommand,
    aliases: *const CommandAliasMap,
) !bool {
    const token = args[index.*];
    if (std.mem.eql(u8, token, "--move-call")) {
        if (index.* + 3 >= args.len) return error.InvalidCli;
        if (index.* + 5 < args.len and
            !std.mem.startsWith(u8, args[index.* + 4], "--") and
            !std.mem.startsWith(u8, args[index.* + 5], "--"))
        {
            try appendTypedMoveCallCommandValue(
                allocator,
                parsed,
                aliases,
                args[index.* + 1],
                args[index.* + 2],
                args[index.* + 3],
                args[index.* + 4],
                args[index.* + 5],
            );
            index.* += 6;
            return true;
        }

        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .move_call = try PendingTypedMoveCall.init(
            allocator,
            args[index.* + 1],
            args[index.* + 2],
            args[index.* + 3],
        ) };
        index.* += 4;
        return true;
    }
    if (std.mem.eql(u8, token, "--move-call-type-arg")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .move_call => |*move_call| try move_call.appendTypeArg(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--move-call-arg")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .move_call => |*move_call| try move_call.appendArg(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--publish")) {
        if (index.* + 2 < args.len and
            !std.mem.startsWith(u8, args[index.* + 1], "--") and
            !std.mem.startsWith(u8, args[index.* + 2], "--"))
        {
            try appendTypedPublishCommandValue(
                allocator,
                parsed,
                args[index.* + 1],
                args[index.* + 2],
            );
            index.* += 3;
            return true;
        }
        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .publish = .{} };
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, token, "--publish-modules")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .publish => |*publish| try publish.setModules(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--publish-dependencies")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .publish => |*publish| try publish.setDependencies(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--transfer-objects")) {
        if (index.* + 2 < args.len and
            !std.mem.startsWith(u8, args[index.* + 1], "--") and
            !std.mem.startsWith(u8, args[index.* + 2], "--"))
        {
            try appendTypedCommandValue(allocator, parsed, aliases, token, args[index.* + 1], args[index.* + 2]);
            index.* += 3;
            return true;
        }
        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .transfer_objects = .{} };
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, token, "--transfer-object")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .transfer_objects => |*transfer| try transfer.appendObject(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--transfer-address")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .transfer_objects => |*transfer| try transfer.setAddress(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--split-coins")) {
        if (index.* + 2 < args.len and
            !std.mem.startsWith(u8, args[index.* + 1], "--") and
            !std.mem.startsWith(u8, args[index.* + 2], "--"))
        {
            try appendTypedCommandValue(allocator, parsed, aliases, token, args[index.* + 1], args[index.* + 2]);
            index.* += 3;
            return true;
        }
        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .split_coins = .{} };
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, token, "--split-coin")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .split_coins => |*split| try split.setCoin(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--split-amount")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .split_coins => |*split| try split.appendAmount(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--merge-coins")) {
        if (index.* + 2 < args.len and
            !std.mem.startsWith(u8, args[index.* + 1], "--") and
            !std.mem.startsWith(u8, args[index.* + 2], "--"))
        {
            try appendTypedCommandValue(allocator, parsed, aliases, token, args[index.* + 1], args[index.* + 2]);
            index.* += 3;
            return true;
        }
        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .merge_coins = .{} };
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, token, "--upgrade")) {
        if (index.* + 4 < args.len and
            !std.mem.startsWith(u8, args[index.* + 1], "--") and
            !std.mem.startsWith(u8, args[index.* + 2], "--") and
            !std.mem.startsWith(u8, args[index.* + 3], "--") and
            !std.mem.startsWith(u8, args[index.* + 4], "--"))
        {
            try appendTypedUpgradeCommandValue(
                allocator,
                parsed,
                aliases,
                args[index.* + 1],
                args[index.* + 2],
                args[index.* + 3],
                args[index.* + 4],
            );
            index.* += 5;
            return true;
        }
        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .upgrade = .{} };
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, token, "--make-move-vec")) {
        if (index.* + 2 < args.len and
            !std.mem.startsWith(u8, args[index.* + 1], "--") and
            !std.mem.startsWith(u8, args[index.* + 2], "--"))
        {
            try appendTypedMakeMoveVecCommandValue(
                allocator,
                parsed,
                aliases,
                args[index.* + 1],
                args[index.* + 2],
            );
            index.* += 3;
            return true;
        }
        if (pending_command.* != null) return error.InvalidCli;
        pending_command.* = .{ .make_move_vec = .{} };
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, token, "--upgrade-modules")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .upgrade => |*upgrade| try upgrade.setModules(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--upgrade-dependencies")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .upgrade => |*upgrade| try upgrade.setDependencies(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--upgrade-package")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .upgrade => |*upgrade| try upgrade.setPackage(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--upgrade-ticket")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .upgrade => |*upgrade| try upgrade.setTicket(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--merge-destination")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .merge_coins => |*merge| try merge.setDestination(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--merge-source")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .merge_coins => |*merge| try merge.appendSource(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--make-move-vec-type")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .make_move_vec => |*make_move_vec| try make_move_vec.setType(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    if (std.mem.eql(u8, token, "--make-move-vec-element")) {
        if (index.* + 1 >= args.len) return error.InvalidCli;
        if (pending_command.*) |*pending| switch (pending.*) {
            .make_move_vec => |*make_move_vec| try make_move_vec.appendElement(allocator, args[index.* + 1]),
            else => return error.InvalidCli,
        } else {
            return error.InvalidCli;
        }
        index.* += 2;
        return true;
    }
    return false;
}

fn tryParseAssignOption(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    args: []const []const u8,
    index: *usize,
    aliases: *CommandAliasMap,
) !bool {
    if (!std.mem.eql(u8, args[index.*], "--assign")) return false;
    if (index.* + 1 >= args.len) return error.InvalidCli;
    try assignCommandAlias(allocator, parsed, aliases, args[index.* + 1]);
    index.* += 2;
    return true;
}

fn parseSignatureArgument(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    raw: []const u8,
    is_file: bool,
) !void {
    if (!is_file) {
        return appendSignatureValue(allocator, parsed, raw);
    }

    const path = if (std.mem.startsWith(u8, raw, "@")) blk: {
        if (raw.len == 1) return error.InvalidCli;
        break :blk raw[1..];
    } else raw;

    return appendSignatureFileValue(allocator, parsed, path);
}

fn setOptionalFileBackedArg(
    allocator: std.mem.Allocator,
    owned_slot: *?[]const u8,
    value_slot: *?[]const u8,
    raw: []const u8,
) !void {
    if (owned_slot.*) |owned| allocator.free(owned);

    const loaded = try maybeLoadFileValue(allocator, raw);
    if (loaded.owned) {
        owned_slot.* = loaded.value;
    }
    value_slot.* = loaded.value;
}

fn setOptionalStringArg(
    allocator: std.mem.Allocator,
    _: *ParsedArgs,
    raw: []const u8,
    owned_slot: *?[]const u8,
    value_slot: *?[]const u8,
) !void {
    if (owned_slot.*) |old| {
        allocator.free(old);
        owned_slot.* = null;
    }

    const loaded = try maybeLoadFileValue(allocator, raw);
    if (loaded.owned) owned_slot.* = loaded.value;
    value_slot.* = loaded.value;
}

fn setOptionalPackageArg(
    allocator: std.mem.Allocator,
    _: *ParsedArgs,
    raw: []const u8,
    owned_slot: *?[]const u8,
    value_slot: *?[]const u8,
) !void {
    if (owned_slot.*) |old| {
        allocator.free(old);
        owned_slot.* = null;
    }

    const loaded = try maybeLoadPackageValue(allocator, raw);
    if (loaded.owned) owned_slot.* = loaded.value;
    value_slot.* = loaded.value;
}

fn setOptionalObjectIdArg(
    allocator: std.mem.Allocator,
    _: *ParsedArgs,
    raw: []const u8,
    owned_slot: *?[]const u8,
    value_slot: *?[]const u8,
) !void {
    if (owned_slot.*) |old| {
        allocator.free(old);
        owned_slot.* = null;
    }

    const loaded = try maybeLoadObjectIdValue(allocator, raw);
    if (loaded.owned) owned_slot.* = loaded.value;
    value_slot.* = loaded.value;
}

fn setOwnedRpcUrl(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
    raw: []const u8,
) !void {
    if (parsed.owned_rpc_url) |old| {
        allocator.free(old);
        parsed.owned_rpc_url = null;
    }

    const loaded = try maybeLoadFileValue(allocator, raw);
    if (loaded.owned) {
        parsed.owned_rpc_url = loaded.value;
    }
    parsed.rpc_url = loaded.value;
    parsed.has_rpc_url = true;
}

fn finalizeStructuredMoveCallArgs(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
) !void {
    if (parsed.tx_build_type_args != null and parsed.tx_build_type_arg_items.items.len > 0) {
        return error.InvalidCli;
    }
    if (parsed.tx_build_args != null and parsed.tx_build_arg_items.items.len > 0) {
        return error.InvalidCli;
    }

    if (parsed.tx_build_type_arg_items.items.len > 0) {
        const value = try tx_builder.buildJsonStringArray(allocator, parsed.tx_build_type_arg_items.items);
        parsed.owned_tx_build_type_args = value;
        parsed.tx_build_type_args = value;
    }
    if (parsed.tx_build_args) |raw_args| {
        const value = if (try moveCallArgsContainSelectedRequestTokens(allocator, raw_args))
            try allocator.dupe(u8, std.mem.trim(u8, raw_args, " \n\r\t"))
        else
            try tx_request_builder.normalizeArgumentValueJsonArray(
                allocator,
                null,
                raw_args,
            );
        if (parsed.owned_tx_build_args) |owned_value| allocator.free(owned_value);
        parsed.owned_tx_build_args = value;
        parsed.tx_build_args = value;
    } else if (parsed.tx_build_arg_items.items.len > 0) {
        const value = if (try moveCallArgItemsContainSelectedRequestTokens(allocator, parsed.tx_build_arg_items.items))
            try tx_builder.buildJsonStringArray(allocator, parsed.tx_build_arg_items.items)
        else
            try tx_request_builder.buildArgumentValueTokenArray(
                allocator,
                null,
                parsed.tx_build_arg_items.items,
            );
        parsed.owned_tx_build_args = value;
        parsed.tx_build_args = value;
    }
}

fn finalizeMoveFunctionIndexedArgs(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
) !void {
    if (parsed.move_function_indexed_arg_items.items.len == 0) return;
    const value = try buildMoveFunctionIndexedArgsJson(
        allocator,
        parsed.move_function_indexed_arg_indices.items,
        parsed.move_function_indexed_arg_items.items,
    );
    if (parsed.owned_move_function_indexed_args_json) |owned| allocator.free(owned);
    parsed.owned_move_function_indexed_args_json = value;
    parsed.move_function_indexed_args_json = value;
}

fn finalizeMoveFunctionIndexedObjectArgs(
    allocator: std.mem.Allocator,
    parsed: *ParsedArgs,
) !void {
    if (parsed.move_function_indexed_object_arg_items.items.len == 0) return;
    const value = try buildMoveFunctionIndexedObjectArgsJson(
        allocator,
        parsed.move_function_indexed_object_arg_indices.items,
        parsed.move_function_indexed_object_arg_items.items,
    );
    if (parsed.owned_move_function_indexed_object_args_json) |owned| allocator.free(owned);
    parsed.owned_move_function_indexed_object_args_json = value;
    parsed.move_function_indexed_object_args_json = value;
}

fn tokenStartsSelectedRequest(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    return std.mem.startsWith(u8, trimmed, "select:") or std.mem.startsWith(u8, trimmed, "sel:");
}

fn validateSelectedRequestToken(allocator: std.mem.Allocator, token: []const u8) !void {
    var owned = try sui.rpc_client.SuiRpcClient.parseSelectedArgumentRequestToken(allocator, token);
    defer owned.deinit(allocator);
}

fn validateSelectedRequestTokensInJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !bool {
    return switch (value) {
        .string => |text| blk: {
            if (!tokenStartsSelectedRequest(text)) break :blk false;
            try validateSelectedRequestToken(allocator, text);
            break :blk true;
        },
        .array => |array| blk: {
            var found = false;
            for (array.items) |item| {
                found = (try validateSelectedRequestTokensInJsonValue(allocator, item)) or found;
            }
            break :blk found;
        },
        .object => |object| blk: {
            var found = false;
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                found = (try validateSelectedRequestTokensInJsonValue(allocator, entry.value_ptr.*)) or found;
            }
            break :blk found;
        },
        else => false,
    };
}

fn moveCallArgsContainSelectedRequestTokens(
    allocator: std.mem.Allocator,
    raw_args: []const u8,
) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_args, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;
    return try validateSelectedRequestTokensInJsonValue(allocator, parsed.value);
}

fn moveCallArgItemsContainSelectedRequestTokens(
    allocator: std.mem.Allocator,
    items: []const []const u8,
) !bool {
    var found = false;
    for (items) |item| {
        if (!tokenStartsSelectedRequest(item)) continue;
        try validateSelectedRequestToken(allocator, item);
        found = true;
    }
    return found;
}

pub fn parseCliArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    var parsed: ParsedArgs = .{};
    var simulate_positional_params = false;
    var send_positional_params = false;
    var pending_typed_command: ?PendingTypedCommand = null;
    var command_aliases = CommandAliasMap{};
    var parsed_ok = false;
    errdefer if (!parsed_ok) parsed.deinit(allocator);
    errdefer if (pending_typed_command) |*pending| pending.deinit(allocator);
    defer deinitCommandAliases(allocator, &command_aliases);

    if (args.len == 0) {
        parsed.show_usage = true;
        parsed.command = .help;
        parsed_ok = true;
        return parsed;
    }

    var i: usize = 0;
    while (i < args.len) {
        const token = args[i];

        if (std.mem.eql(u8, token, "-h") or std.mem.eql(u8, token, "--help")) {
            parsed.show_usage = true;
            parsed.command = .help;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--version")) {
            parsed.command = .version;
            parsed.has_command = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--rpc")) {
            if (i + 1 >= args.len) return error.InvalidCli;
            const raw_rpc = args[i + 1];
            try setOwnedRpcUrl(allocator, &parsed, raw_rpc);
            i += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--timeout-ms")) {
            if (i + 1 >= args.len) return error.InvalidCli;
            parsed.request_timeout_ms = try parseIntValue(args[i + 1]);
            i += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--confirm-timeout-ms")) {
            if (i + 1 >= args.len) return error.InvalidCli;
            parsed.confirm_timeout_ms = try parseIntValue(args[i + 1]);
            i += 2;
            continue;
        }

        if (std.mem.eql(u8, token, "--pretty")) {
            parsed.pretty = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--poll-ms")) {
            if (i + 1 >= args.len) return error.InvalidCli;
            parsed.confirm_poll_ms = try parseIntValue(args[i + 1]);
            if (parsed.confirm_poll_ms == 0) return error.InvalidCli;
            i += 2;
            continue;
        }

        if (!parsed.has_command) {
            if (std.mem.eql(u8, token, "help")) {
                parsed.command = .help;
                parsed.has_command = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "version")) {
                parsed.command = .version;
                parsed.has_command = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "rpc")) {
                parsed.command = .rpc;
                parsed.has_command = true;
                i += 1;
                if (i >= args.len or std.mem.startsWith(u8, args[i], "--")) return error.InvalidCli;
                parsed.method = args[i];
                i += 1;
                if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                    const raw_params = args[i];
                    try setOptionalStringArg(allocator, &parsed, raw_params, &parsed.owned_params, &parsed.params);
                    i += 1;
                } else {
                    parsed.params = "[]";
                }
                continue;
            }
            if (std.mem.eql(u8, token, "tx")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "simulate")) {
                    parsed.command = .tx_simulate;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        const raw_params = args[i];
                        simulate_positional_params = true;
                        try setOptionalStringArg(allocator, &parsed, raw_params, &parsed.owned_params, &parsed.params);
                        i += 1;
                    } else {
                        parsed.params = "[]";
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "dry-run") or std.mem.eql(u8, sub, "dry_run") or std.mem.eql(u8, sub, "dryrun")) {
                    parsed.command = .tx_dry_run;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        try setOptionalFileBackedArg(
                            allocator,
                            &parsed.owned_tx_bytes,
                            &parsed.tx_bytes,
                            args[i],
                        );
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "send")) {
                    parsed.command = .tx_send;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        const raw_params = args[i];
                        send_positional_params = true;
                        try setOptionalFileBackedArg(
                            allocator,
                            &parsed.owned_tx_bytes,
                            &parsed.tx_bytes,
                            raw_params,
                        );
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "payload")) {
                    parsed.command = .tx_payload;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "build")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .tx_build;
                    parsed.has_command = true;

                    const sub_build = args[i + 2];
                    if (std.mem.eql(u8, sub_build, "move-call") or std.mem.eql(u8, sub_build, "move_call")) {
                        parsed.tx_build_kind = .move_call;
                    } else if (std.mem.eql(u8, sub_build, "programmable")) {
                        parsed.tx_build_kind = .programmable;
                        parsed.tx_build_emit_tx_block = true;
                    } else {
                        return error.InvalidCli;
                    }
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "confirm") or std.mem.eql(u8, sub, "wait")) {
                    parsed.command = .tx_confirm;
                    parsed.has_command = true;
                    i += 2;
                    if (i >= args.len) return error.InvalidCli;
                    parsed.tx_digest = args[i];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, sub, "status")) {
                    parsed.command = .tx_status;
                    parsed.has_command = true;
                    i += 2;
                    if (i >= args.len) return error.InvalidCli;
                    parsed.tx_digest = args[i];
                    i += 1;
                    continue;
                }
                return error.InvalidCli;
            }

            if (std.mem.eql(u8, token, "account")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "list")) {
                    parsed.command = .account_list;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "info")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .account_info;
                    parsed.has_command = true;
                    parsed.account_selector = args[i + 2];
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "coins")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .account_coins;
                    parsed.has_command = true;
                    parsed.account_selector = args[i + 2];
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "objects")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .account_objects;
                    parsed.has_command = true;
                    parsed.account_selector = args[i + 2];
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "resources")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .account_resources;
                    parsed.has_command = true;
                    parsed.account_selector = args[i + 2];
                    i += 3;
                    continue;
                }

                return error.InvalidCli;
            }

            if (std.mem.eql(u8, token, "wallet")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "create")) {
                    parsed.command = .wallet_create;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "intent")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    const intent_sub = args[i + 2];
                    if (std.mem.eql(u8, intent_sub, "build")) {
                        parsed.command = .wallet_intent_build;
                        parsed.has_command = true;
                        i += 3;
                        continue;
                    }
                    if (std.mem.eql(u8, intent_sub, "dry-run") or std.mem.eql(u8, intent_sub, "dry_run") or std.mem.eql(u8, intent_sub, "dryrun")) {
                        parsed.command = .wallet_intent_dry_run;
                        parsed.has_command = true;
                        i += 3;
                        continue;
                    }
                    if (std.mem.eql(u8, intent_sub, "send")) {
                        parsed.command = .wallet_intent_send;
                        parsed.has_command = true;
                        i += 3;
                        continue;
                    }
                    return error.InvalidCli;
                }
                if (std.mem.eql(u8, sub, "import")) {
                    parsed.command = .wallet_import;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i],
                            &parsed.owned_wallet_private_key,
                            &parsed.wallet_private_key,
                        );
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "use")) {
                    parsed.command = .wallet_use;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.account_selector = args[i];
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "export-public") or std.mem.eql(u8, sub, "export_public")) {
                    parsed.command = .wallet_export_public;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.account_selector = args[i];
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "signer")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    const signer_sub = args[i + 2];
                    if (std.mem.eql(u8, signer_sub, "inspect")) {
                        parsed.command = .wallet_signer_inspect;
                        parsed.has_command = true;
                        i += 3;
                        if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                            parsed.account_selector = args[i];
                            i += 1;
                        }
                        continue;
                    }
                    return error.InvalidCli;
                }
                if (std.mem.eql(u8, sub, "address")) {
                    parsed.command = .wallet_address;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.account_selector = args[i];
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "balance")) {
                    parsed.command = .wallet_balance;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.account_selector = args[i];
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "coins")) {
                    parsed.command = .wallet_coins;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.account_selector = args[i];
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "objects")) {
                    parsed.command = .wallet_objects;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.account_selector = args[i];
                        i += 1;
                    }
                    continue;
                }

                return error.InvalidCli;
            }

            if (std.mem.eql(u8, token, "request")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "build")) {
                    parsed.command = .request_build;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "inspect")) {
                    parsed.command = .request_inspect;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "dry-run") or std.mem.eql(u8, sub, "dry_run") or std.mem.eql(u8, sub, "dryrun")) {
                    parsed.command = .request_dry_run;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "sponsor")) {
                    parsed.command = .request_sponsor;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "sign")) {
                    parsed.command = .request_sign;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "send")) {
                    parsed.command = .request_send;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "schedule")) {
                    parsed.command = .request_schedule;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "list")) {
                    parsed.command = .request_list;
                    parsed.has_command = true;
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, sub, "cancel")) {
                    parsed.command = .request_cancel;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i],
                            &parsed.owned_request_entry_id,
                            &parsed.request_entry_id,
                        );
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "resume")) {
                    parsed.command = .request_resume;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i],
                            &parsed.owned_request_entry_id,
                            &parsed.request_entry_id,
                        );
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "rebroadcast")) {
                    parsed.command = .request_rebroadcast;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i],
                            &parsed.owned_request_entry_id,
                            &parsed.request_entry_id,
                        );
                        i += 1;
                    }
                    continue;
                }
                if (std.mem.eql(u8, sub, "status")) {
                    parsed.command = .request_status;
                    parsed.has_command = true;
                    i += 2;
                    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
                        parsed.tx_digest = args[i];
                        i += 1;
                    }
                    continue;
                }

                return error.InvalidCli;
            }

            if (std.mem.eql(u8, token, "events")) {
                parsed.command = .events;
                parsed.has_command = true;
                i += 1;
                continue;
            }

            if (std.mem.eql(u8, token, "move")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "package")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .move_package;
                    parsed.has_command = true;
                    try setOptionalPackageArg(
                        allocator,
                        &parsed,
                        args[i + 2],
                        &parsed.owned_move_package,
                        &parsed.move_package,
                    );
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "module")) {
                    if (i + 3 >= args.len) return error.InvalidCli;
                    parsed.command = .move_module;
                    parsed.has_command = true;
                    try setOptionalPackageArg(
                        allocator,
                        &parsed,
                        args[i + 2],
                        &parsed.owned_move_package,
                        &parsed.move_package,
                    );
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 3],
                        &parsed.owned_move_module,
                        &parsed.move_module,
                    );
                    i += 4;
                    continue;
                }
                if (std.mem.eql(u8, sub, "function")) {
                    if (i + 4 >= args.len) return error.InvalidCli;
                    parsed.command = .move_function;
                    parsed.has_command = true;
                    try setOptionalPackageArg(
                        allocator,
                        &parsed,
                        args[i + 2],
                        &parsed.owned_move_package,
                        &parsed.move_package,
                    );
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 3],
                        &parsed.owned_move_module,
                        &parsed.move_module,
                    );
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 4],
                        &parsed.owned_move_function,
                        &parsed.move_function,
                    );
                    i += 5;
                    continue;
                }

                return error.InvalidCli;
            }

            if (std.mem.eql(u8, token, "object")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "get")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .object_get;
                    parsed.has_command = true;
                    try setOptionalObjectIdArg(
                        allocator,
                        &parsed,
                        args[i + 2],
                        &parsed.owned_object_id,
                        &parsed.object_id,
                    );
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "dynamic-fields") or std.mem.eql(u8, sub, "dynamic_fields")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .object_dynamic_fields;
                    parsed.has_command = true;
                    try setOptionalObjectIdArg(
                        allocator,
                        &parsed,
                        args[i + 2],
                        &parsed.owned_object_parent_id,
                        &parsed.object_parent_id,
                    );
                    i += 3;
                    continue;
                }
                if (std.mem.eql(u8, sub, "dynamic-field-object") or std.mem.eql(u8, sub, "dynamic_field_object")) {
                    if (i + 2 >= args.len) return error.InvalidCli;
                    parsed.command = .object_dynamic_field_object;
                    parsed.has_command = true;
                    try setOptionalObjectIdArg(
                        allocator,
                        &parsed,
                        args[i + 2],
                        &parsed.owned_object_parent_id,
                        &parsed.object_parent_id,
                    );
                    if (i + 3 < args.len and !std.mem.startsWith(u8, args[i + 3], "--")) {
                        try setOptionalFileBackedArg(
                            allocator,
                            &parsed.owned_object_dynamic_field_name,
                            &parsed.object_dynamic_field_name,
                            args[i + 3],
                        );
                        i += 4;
                    } else {
                        i += 3;
                    }
                    continue;
                }
                return error.InvalidCli;
            }

            return error.InvalidCli;
        }

        if (parsed.command == .rpc) {
            if (std.mem.eql(u8, token, "--params")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const raw_params = args[i + 1];
                try setOptionalStringArg(allocator, &parsed, raw_params, &parsed.owned_params, &parsed.params);
                i += 2;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .tx_simulate) {
            try maybeFlushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases, token);
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_package,
                    &parsed.tx_build_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_module,
                    &parsed.tx_build_module,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--function")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_function,
                    &parsed.tx_build_function,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_type_args,
                    &parsed.tx_build_type_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_type_arg_items,
                    &parsed.owned_tx_build_type_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_args,
                    &parsed.tx_build_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_arg_items,
                    &parsed.owned_tx_build_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--commands")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--command")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (try tryParseAssignOption(allocator, &parsed, args, &i, &command_aliases)) {
                continue;
            }
            if (try tryParseTypedCommandOption(allocator, &parsed, args, &i, &pending_typed_command, &command_aliases)) {
                continue;
            }
            if (std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_sender,
                    &parsed.tx_build_sender,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-budget")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_budget = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-price")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_price = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_build_gas_payment, &parsed.tx_build_gas_payment, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--auto-gas-payment")) {
                parsed.tx_build_auto_gas_payment = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment-min-balance")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_payment_min_balance = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--session-response")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_session_response,
                    &parsed.tx_session_response,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--provider")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_provider_config,
                    &parsed.tx_provider_config,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--signer")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendSignerValue(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--options")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_options, &parsed.tx_options, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--params")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const raw_params = args[i + 1];
                try setOptionalStringArg(allocator, &parsed, raw_params, &parsed.owned_params, &parsed.params);
                i += 2;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .tx_dry_run) {
            try maybeFlushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases, token);
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--request")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try applyProgrammaticRequestArtifact(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_package,
                    &parsed.tx_build_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_module,
                    &parsed.tx_build_module,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--function")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_function,
                    &parsed.tx_build_function,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_type_args,
                    &parsed.tx_build_type_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_type_arg_items,
                    &parsed.owned_tx_build_type_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_args,
                    &parsed.tx_build_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_arg_items,
                    &parsed.owned_tx_build_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--tx-bytes")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_bytes, &parsed.tx_bytes, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--commands")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--command")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (try tryParseAssignOption(allocator, &parsed, args, &i, &command_aliases)) {
                continue;
            }
            if (try tryParseTypedCommandOption(allocator, &parsed, args, &i, &pending_typed_command, &command_aliases)) {
                continue;
            }
            if (std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_sender,
                    &parsed.tx_build_sender,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-budget")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_budget = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-price")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_price = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_build_gas_payment, &parsed.tx_build_gas_payment, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--auto-gas-payment")) {
                parsed.tx_build_auto_gas_payment = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment-min-balance")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_payment_min_balance = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--signer")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendSignerValue(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--from-keystore")) {
                parsed.from_keystore = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .tx_send) {
            try maybeFlushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases, token);
            if (std.mem.eql(u8, token, "--request")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try applyProgrammaticRequestArtifact(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_package,
                    &parsed.tx_build_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_module,
                    &parsed.tx_build_module,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--function")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_function,
                    &parsed.tx_build_function,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_type_args,
                    &parsed.tx_build_type_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_type_arg_items,
                    &parsed.owned_tx_build_type_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_args,
                    &parsed.tx_build_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_arg_items,
                    &parsed.owned_tx_build_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--from-keystore")) {
                parsed.from_keystore = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--params")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                const raw_params = args[i + 1];
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_bytes, &parsed.tx_bytes, raw_params);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--tx-bytes")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_bytes, &parsed.tx_bytes, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--wait")) {
                parsed.tx_send_wait = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--observe")) {
                parsed.tx_send_observe = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--session-response")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_session_response,
                    &parsed.tx_session_response,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--provider")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_provider_config,
                    &parsed.tx_provider_config,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--signature") or std.mem.eql(u8, token, "--sig") or std.mem.eql(u8, token, "--signature-file")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try parseSignatureArgument(allocator, &parsed, args[i + 1], std.mem.eql(u8, token, "--signature-file"));
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--commands")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--command")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (try tryParseAssignOption(allocator, &parsed, args, &i, &command_aliases)) {
                continue;
            }
            if (try tryParseTypedCommandOption(allocator, &parsed, args, &i, &pending_typed_command, &command_aliases)) {
                continue;
            }
            if (std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_sender,
                    &parsed.tx_build_sender,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-budget")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_budget = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-price")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_price = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_build_gas_payment, &parsed.tx_build_gas_payment, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--auto-gas-payment")) {
                parsed.tx_build_auto_gas_payment = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment-min-balance")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_payment_min_balance = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--wait")) {
                parsed.tx_send_wait = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--signer")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendSignerValue(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--options")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_options, &parsed.tx_options, args[i + 1]);
                i += 2;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .tx_build) {
            try maybeFlushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases, token);
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_package,
                    &parsed.tx_build_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_module,
                    &parsed.tx_build_module,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--function")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_function,
                    &parsed.tx_build_function,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_type_args,
                    &parsed.tx_build_type_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_type_arg_items,
                    &parsed.owned_tx_build_type_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_args,
                    &parsed.tx_build_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_arg_items,
                    &parsed.owned_tx_build_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--commands")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--command")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (try tryParseAssignOption(allocator, &parsed, args, &i, &command_aliases)) {
                continue;
            }
            if (try tryParseTypedCommandOption(allocator, &parsed, args, &i, &pending_typed_command, &command_aliases)) {
                continue;
            }
            if (std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_sender,
                    &parsed.tx_build_sender,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--signer")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendSignerValue(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-budget")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_budget = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-price")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_price = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_build_gas_payment, &parsed.tx_build_gas_payment, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--auto-gas-payment")) {
                parsed.tx_build_auto_gas_payment = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment-min-balance")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_payment_min_balance = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--session-response")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_session_response,
                    &parsed.tx_session_response,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--provider")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_provider_config,
                    &parsed.tx_provider_config,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--emit-tx-block") or std.mem.eql(u8, token, "--tx-block")) {
                parsed.tx_build_emit_tx_block = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .tx_payload) {
            try maybeFlushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases, token);
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_package,
                    &parsed.tx_build_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_module,
                    &parsed.tx_build_module,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--function")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_function,
                    &parsed.tx_build_function,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_type_args,
                    &parsed.tx_build_type_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--type-arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_type_arg_items,
                    &parsed.owned_tx_build_type_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_args,
                    &parsed.tx_build_args,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_arg_items,
                    &parsed.owned_tx_build_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--from-keystore")) {
                parsed.from_keystore = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--commands")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--command")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                i += 2;
                continue;
            }
            if (try tryParseAssignOption(allocator, &parsed, args, &i, &command_aliases)) {
                continue;
            }
            if (try tryParseTypedCommandOption(allocator, &parsed, args, &i, &pending_typed_command, &command_aliases)) {
                continue;
            }
            if (std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_sender,
                    &parsed.tx_build_sender,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-budget")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_budget = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-price")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_price = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_build_gas_payment, &parsed.tx_build_gas_payment, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--auto-gas-payment")) {
                parsed.tx_build_auto_gas_payment = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--gas-payment-min-balance")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.tx_build_gas_payment_min_balance = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--session-response")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_session_response,
                    &parsed.tx_session_response,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--provider")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_provider_config,
                    &parsed.tx_provider_config,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--tx-bytes")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_bytes, &parsed.tx_bytes, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--signature") or std.mem.eql(u8, token, "--sig") or std.mem.eql(u8, token, "--signature-file")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try parseSignatureArgument(allocator, &parsed, args[i + 1], std.mem.eql(u8, token, "--signature-file"));
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--signer")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendSignerValue(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--options")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(allocator, &parsed.owned_tx_options, &parsed.tx_options, args[i + 1]);
                i += 2;
                continue;
            }
            return error.InvalidCli;
        }

        if (isRequestLifecycleCommand(parsed.command)) {
            try maybeFlushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases, token);
            if (isWalletIntentLifecycleCommand(parsed.command) and std.mem.eql(u8, token, "--intent")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try applyWalletIntentArtifact(allocator, &parsed, args[i + 1]);
                i += 2;
                continue;
            }
            if (requestLifecycleConsumesRequestArtifact(parsed.command)) {
                if (std.mem.eql(u8, token, "--request")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try applyProgrammaticRequestArtifact(allocator, &parsed, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--package")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalPackageArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_tx_build_package,
                        &parsed.tx_build_package,
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--module")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_tx_build_module,
                        &parsed.tx_build_module,
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--function")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_tx_build_function,
                        &parsed.tx_build_function,
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--type-args")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_tx_build_type_args,
                        &parsed.tx_build_type_args,
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--type-arg")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try appendRepeatedLoadedValue(
                        allocator,
                        &parsed.tx_build_type_arg_items,
                        &parsed.owned_tx_build_type_arg_items,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--args")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_tx_build_args,
                        &parsed.tx_build_args,
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--arg")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try appendRepeatedLoadedValue(
                        allocator,
                        &parsed.tx_build_arg_items,
                        &parsed.owned_tx_build_arg_items,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--commands")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--command")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try appendCommandValue(allocator, &parsed, &command_aliases, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (try tryParseAssignOption(allocator, &parsed, args, &i, &command_aliases)) {
                    continue;
                }
                if (try tryParseTypedCommandOption(allocator, &parsed, args, &i, &pending_typed_command, &command_aliases)) {
                    continue;
                }
                if (std.mem.eql(u8, token, "--sender")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_tx_build_sender,
                        &parsed.tx_build_sender,
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--gas-budget")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    parsed.tx_build_gas_budget = try parseIntValue(args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--gas-price")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    parsed.tx_build_gas_price = try parseIntValue(args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--gas-payment")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(allocator, &parsed.owned_tx_build_gas_payment, &parsed.tx_build_gas_payment, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--auto-gas-payment")) {
                    parsed.tx_build_auto_gas_payment = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--auto-gas-budget")) {
                    parsed.tx_build_auto_gas_budget = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--gas-payment-min-balance")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    parsed.tx_build_gas_payment_min_balance = try parseIntValue(args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--signature") or std.mem.eql(u8, token, "--sig") or std.mem.eql(u8, token, "--signature-file")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try parseSignatureArgument(allocator, &parsed, args[i + 1], std.mem.eql(u8, token, "--signature-file"));
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--signer")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try appendSignerValue(allocator, &parsed, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--from-keystore")) {
                    parsed.from_keystore = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--options")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(allocator, &parsed.owned_tx_options, &parsed.tx_options, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (isWalletIntentLifecycleCommand(parsed.command) and std.mem.eql(u8, token, "--network")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_intent_network,
                        &parsed.intent_network,
                    );
                    i += 2;
                    continue;
                }
                if (isWalletIntentLifecycleCommand(parsed.command) and std.mem.eql(u8, token, "--execution-mode")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalStringArg(
                        allocator,
                        &parsed,
                        args[i + 1],
                        &parsed.owned_intent_execution_mode,
                        &parsed.intent_execution_mode,
                    );
                    i += 2;
                    continue;
                }
                if (isWalletIntentLifecycleCommand(parsed.command) and (std.mem.eql(u8, token, "--policy") or std.mem.eql(u8, token, "--intent-policy"))) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(
                        allocator,
                        &parsed.owned_intent_policy_json,
                        &parsed.intent_policy_json,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
                if (parsed.command == .request_sponsor or
                    parsed.command == .request_schedule or
                    isWalletIntentLifecycleCommand(parsed.command))
                {
                    if (std.mem.eql(u8, token, "--sponsor-mode")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i + 1],
                            &parsed.owned_request_sponsor_mode,
                            &parsed.request_sponsor_mode,
                        );
                        i += 2;
                        continue;
                    }
                    if (std.mem.eql(u8, token, "--sponsor-policy")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        try setOptionalFileBackedArg(
                            allocator,
                            &parsed.owned_request_sponsor_policy,
                            &parsed.request_sponsor_policy,
                            args[i + 1],
                        );
                        i += 2;
                        continue;
                    }
                    if (std.mem.eql(u8, token, "--valid-after-ms")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        parsed.request_valid_after_ms = try parseIntValue(args[i + 1]);
                        i += 2;
                        continue;
                    }
                    if (std.mem.eql(u8, token, "--valid-before-ms")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        parsed.request_valid_before_ms = try parseIntValue(args[i + 1]);
                        i += 2;
                        continue;
                    }
                    if (std.mem.eql(u8, token, "--correlation-id")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i + 1],
                            &parsed.owned_request_correlation_id,
                            &parsed.request_correlation_id,
                        );
                        i += 2;
                        continue;
                    }
                }
                if (parsed.command == .request_schedule) {
                    if (std.mem.eql(u8, token, "--schedule-id")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i + 1],
                            &parsed.owned_request_schedule_id,
                            &parsed.request_schedule_id,
                        );
                        i += 2;
                        continue;
                    }
                    if (std.mem.eql(u8, token, "--replace-schedule-id")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        try setOptionalStringArg(
                            allocator,
                            &parsed,
                            args[i + 1],
                            &parsed.owned_request_schedule_replace_id,
                            &parsed.request_schedule_replace_id,
                        );
                        i += 2;
                        continue;
                    }
                    if (std.mem.eql(u8, token, "--schedule-at-ms")) {
                        if (i + 1 >= args.len) return error.InvalidCli;
                        parsed.request_schedule_at_ms = try parseIntValue(args[i + 1]);
                        i += 2;
                        continue;
                    }
                }
                if (std.mem.eql(u8, token, "--wait")) {
                    parsed.tx_send_wait = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                    parsed.tx_send_summarize = true;
                    i += 1;
                    continue;
                }
                if ((parsed.command == .request_send or parsed.command == .request_rebroadcast or parsed.command == .wallet_intent_send) and std.mem.eql(u8, token, "--observe")) {
                    parsed.tx_send_observe = true;
                    i += 1;
                    continue;
                }
                if (requestLifecycleUsesProviderFlow(parsed.command) and std.mem.eql(u8, token, "--session-response")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(
                        allocator,
                        &parsed.owned_tx_session_response,
                        &parsed.tx_session_response,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
                if (requestLifecycleUsesProviderFlow(parsed.command) and std.mem.eql(u8, token, "--provider")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(
                        allocator,
                        &parsed.owned_tx_provider_config,
                        &parsed.tx_provider_config,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
            }
            if (parsed.command == .request_rebroadcast) {
                if (std.mem.eql(u8, token, "--signature") or std.mem.eql(u8, token, "--sig") or std.mem.eql(u8, token, "--signature-file")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try parseSignatureArgument(allocator, &parsed, args[i + 1], std.mem.eql(u8, token, "--signature-file"));
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--signer")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try appendSignerValue(allocator, &parsed, args[i + 1]);
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--from-keystore")) {
                    parsed.from_keystore = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--wait")) {
                    parsed.tx_send_wait = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                    parsed.tx_send_summarize = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--observe")) {
                    parsed.tx_send_observe = true;
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, token, "--session-response")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(
                        allocator,
                        &parsed.owned_tx_session_response,
                        &parsed.tx_session_response,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
                if (std.mem.eql(u8, token, "--provider")) {
                    if (i + 1 >= args.len) return error.InvalidCli;
                    try setOptionalFileBackedArg(
                        allocator,
                        &parsed.owned_tx_provider_config,
                        &parsed.tx_provider_config,
                        args[i + 1],
                    );
                    i += 2;
                    continue;
                }
            }
            return error.InvalidCli;
        }

        if (parsed.command == .account_list) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_list_json = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .account_info) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_info_json = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .wallet_create or
            parsed.command == .wallet_import or
            parsed.command == .wallet_use or
            parsed.command == .wallet_export_public or
            parsed.command == .wallet_signer_inspect)
        {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.wallet_json = true;
                i += 1;
                continue;
            }
            if ((parsed.command == .wallet_create or parsed.command == .wallet_import) and std.mem.eql(u8, token, "--alias")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_wallet_alias,
                    &parsed.wallet_alias,
                );
                i += 2;
                continue;
            }
            if (parsed.command == .wallet_import and (std.mem.eql(u8, token, "--private-key") or std.mem.eql(u8, token, "--key"))) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_wallet_private_key,
                    &parsed.wallet_private_key,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if ((parsed.command == .wallet_create or parsed.command == .wallet_import) and std.mem.eql(u8, token, "--no-activate")) {
                parsed.wallet_activate = false;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .wallet_balance) {
            if (std.mem.eql(u8, token, "--coin-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coin_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_resources_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.account_resources_all = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .wallet_coins) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_coins_json = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--coin-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coin_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--cursor")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coins_cursor = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coins_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.account_coins_all = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .account_coins) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_coins_json = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--coin-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coin_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--cursor")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coins_cursor = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coins_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.account_coins_all = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .wallet_objects) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_objects_json = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--filter")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_account_objects_filter,
                    &parsed.account_objects_filter,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--struct-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_struct_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--object-id")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_object_id = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_account_objects_package,
                    &parsed.account_objects_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_module = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--cursor")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_cursor = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.account_objects_all = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .account_objects) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_objects_json = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--filter")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_account_objects_filter,
                    &parsed.account_objects_filter,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--struct-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_struct_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--object-id")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_object_id = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_account_objects_package,
                    &parsed.account_objects_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_module = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--cursor")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_cursor = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.account_objects_all = true;
                i += 1;
                continue;
            }
        }

        if (parsed.command == .account_resources) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.account_resources_json = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--coin-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_coin_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--filter")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_account_objects_filter,
                    &parsed.account_objects_filter,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--struct-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_struct_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--object-id")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_object_id = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_account_objects_package,
                    &parsed.account_objects_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_objects_module = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.account_resources_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.account_resources_all = true;
                i += 1;
                continue;
            }
        }

        if (parsed.command == .events) {
            if (std.mem.eql(u8, token, "--json")) {
                parsed.events_json = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--filter")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_event_filter,
                    &parsed.event_filter,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--package")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalPackageArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_event_package,
                    &parsed.event_package,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--module")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_event_module,
                    &parsed.event_module,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--event-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_event_type,
                    &parsed.event_type,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_event_sender,
                    &parsed.event_sender,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--tx")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_event_tx_digest_filter,
                    &parsed.event_tx_digest_filter,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--cursor-tx")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_event_cursor_tx_digest,
                    &parsed.event_cursor_tx_digest,
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--cursor-event")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.event_cursor_event_seq = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.event_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--descending")) {
                parsed.event_descending = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.event_all = true;
                i += 1;
                continue;
            }
        }

        if (parsed.command == .move_package or parsed.command == .move_module or parsed.command == .move_function) {
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--sender")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_sender,
                    &parsed.tx_build_sender,
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--signer")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.signers,
                    &parsed.owned_signers,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--from-keystore")) {
                parsed.from_keystore = true;
                i += 1;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--type-args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_type_args,
                    &parsed.tx_build_type_args,
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--type-arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_type_arg_items,
                    &parsed.owned_tx_build_type_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--args")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalStringArg(
                    allocator,
                    &parsed,
                    args[i + 1],
                    &parsed.owned_tx_build_args,
                    &parsed.tx_build_args,
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--arg")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try appendRepeatedLoadedValue(
                    allocator,
                    &parsed.tx_build_arg_items,
                    &parsed.owned_tx_build_arg_items,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--arg-at")) {
                if (i + 2 >= args.len) return error.InvalidCli;
                try appendIndexedRepeatedLoadedValue(
                    allocator,
                    &parsed.move_function_indexed_arg_indices,
                    &parsed.move_function_indexed_arg_items,
                    &parsed.owned_move_function_indexed_arg_items,
                    args[i + 1],
                    args[i + 2],
                );
                i += 3;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--object-arg-at")) {
                if (i + 2 >= args.len) return error.InvalidCli;
                try appendIndexedRepeatedLoadedObjectIdValue(
                    allocator,
                    &parsed.move_function_indexed_object_arg_indices,
                    &parsed.move_function_indexed_object_arg_items,
                    &parsed.owned_move_function_indexed_object_arg_items,
                    args[i + 1],
                    args[i + 2],
                );
                i += 3;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--emit-template")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.move_function_template_output = try parseMoveFunctionTemplateOutput(args[i + 1]);
                parsed.tx_send_summarize = true;
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--dry-run")) {
                parsed.move_function_execute_dry_run = true;
                i += 1;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--send")) {
                parsed.move_function_execute_send = true;
                i += 1;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--wait")) {
                parsed.tx_send_wait = true;
                i += 1;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--observe")) {
                parsed.tx_send_observe = true;
                i += 1;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--session-response")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_session_response,
                    &parsed.tx_session_response,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (parsed.command == .move_function and std.mem.eql(u8, token, "--provider")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_tx_provider_config,
                    &parsed.tx_provider_config,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .object_get or parsed.command == .account_objects or parsed.command == .wallet_objects or parsed.command == .account_resources) {
            if (std.mem.eql(u8, token, "--options")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_object_options,
                    &parsed.object_options,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-type")) {
                parsed.object_show_type = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-owner")) {
                parsed.object_show_owner = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-previous-transaction")) {
                parsed.object_show_previous_transaction = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-display")) {
                parsed.object_show_display = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-content")) {
                parsed.object_show_content = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-bcs")) {
                parsed.object_show_bcs = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--show-storage-rebate")) {
                parsed.object_show_storage_rebate = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                if (parsed.command != .object_get) return error.InvalidCli;
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .object_dynamic_fields) {
            if (std.mem.eql(u8, token, "--cursor")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.object_dynamic_fields_cursor = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--limit")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.object_dynamic_fields_limit = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--all")) {
                parsed.object_dynamic_fields_all = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .object_dynamic_field_object) {
            if (std.mem.eql(u8, token, "--name-type")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.object_dynamic_field_name_type = args[i + 1];
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--name-value")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                try setOptionalFileBackedArg(
                    allocator,
                    &parsed.owned_object_dynamic_field_name_value,
                    &parsed.object_dynamic_field_name_value,
                    args[i + 1],
                );
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        if (parsed.command == .tx_confirm or parsed.command == .tx_status or parsed.command == .request_status) {
            if (std.mem.eql(u8, token, "--poll-ms")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.confirm_poll_ms = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--confirm-timeout-ms")) {
                if (i + 1 >= args.len) return error.InvalidCli;
                parsed.confirm_timeout_ms = try parseIntValue(args[i + 1]);
                i += 2;
                continue;
            }
            if (std.mem.eql(u8, token, "--summarize") or std.mem.eql(u8, token, "--summary")) {
                parsed.tx_send_summarize = true;
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "--observe")) {
                parsed.tx_send_observe = true;
                i += 1;
                continue;
            }
            return error.InvalidCli;
        }

        return error.InvalidCli;
    }

    try flushPendingTypedCommand(allocator, &parsed, &pending_typed_command, &command_aliases);
    try finalizeStructuredMoveCallArgs(allocator, &parsed);
    try finalizeMoveFunctionIndexedArgs(allocator, &parsed);
    try finalizeMoveFunctionIndexedObjectArgs(allocator, &parsed);

    if (parsed.command == .tx_simulate) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.tx_session_response != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxInput(&parsed) and simulate_positional_params) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .tx_dry_run) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.tx_bytes == null and !hasProgrammaticTxInput(&parsed)) {
            return error.InvalidCli;
        }
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_bytes != null and hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_bytes != null and (parsed.signers.items.len != 0 or parsed.from_keystore)) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .tx_send) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.signatures.items.len == 0 and !parsed.from_keystore and parsed.signers.items.len == 0 and parsed.tx_provider_config == null) {
            return error.InvalidCli;
        }
        if (parsed.tx_bytes == null and !hasProgrammaticTxInput(&parsed)) {
            return error.InvalidCli;
        }
        if (parsed.tx_session_response != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_bytes != null and hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_bytes != null and parsed.tx_provider_config != null) return error.InvalidCli;
        if (hasProgrammaticTxInput(&parsed) and send_positional_params) return error.InvalidCli;
        if (parsed.tx_send_summarize and parsed.tx_send_observe) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .request_send) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.signatures.items.len == 0 and !parsed.from_keystore and parsed.signers.items.len == 0 and parsed.tx_provider_config == null) {
            return error.InvalidCli;
        }
        if (!hasProgrammaticTxInput(&parsed)) {
            return error.InvalidCli;
        }
        if (parsed.tx_session_response != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_send_summarize and parsed.tx_send_observe) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .wallet_intent_send) {
        if (parsed.intent_execution_mode) |value| try wallet_intent.validateExecutionMode(value);
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.signatures.items.len == 0 and !parsed.from_keystore and parsed.signers.items.len == 0 and parsed.tx_provider_config == null) {
            return error.InvalidCli;
        }
        if (!hasProgrammaticTxInput(&parsed)) {
            return error.InvalidCli;
        }
        if (parsed.tx_session_response != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_send_summarize and parsed.tx_send_observe) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .request_rebroadcast) {
        const entry_id = parsed.request_entry_id orelse return error.InvalidCli;
        if (entry_id.len == 0) return error.InvalidCli;
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.tx_send_summarize and parsed.tx_send_observe) return error.InvalidCli;
        if (hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
    }

    if (parsed.command == .request_sign) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (!hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_session_response != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .wallet_intent_dry_run) {
        if (parsed.intent_execution_mode) |value| try wallet_intent.validateExecutionMode(value);
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (!hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if ((parsed.command == .tx_status or parsed.command == .tx_confirm or parsed.command == .request_status) and
        parsed.tx_send_summarize and parsed.tx_send_observe)
    {
        return error.InvalidCli;
    }

    if (parsed.command == .tx_payload) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.tx_bytes == null and !hasProgrammaticTxInput(&parsed)) {
            return error.InvalidCli;
        }
        if (parsed.tx_session_response != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_bytes != null and hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (parsed.tx_bytes != null and parsed.tx_provider_config != null) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (requestLifecycleConsumesRequestArtifact(parsed.command)) {
        if (parsed.intent_execution_mode) |value| try wallet_intent.validateExecutionMode(value);
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        if (parsed.tx_send_summarize and parsed.tx_send_observe) return error.InvalidCli;
        if (hasProgrammaticTxContext(&parsed) and !hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        if (!hasProgrammaticTxInput(&parsed)) return error.InvalidCli;
        try validateProgrammaticTxInput(&parsed);
    }

    if (parsed.command == .tx_build) {
        if (parsed.tx_build_auto_gas_payment and parsed.tx_build_gas_payment != null) return error.InvalidCli;
        if (parsed.tx_build_gas_payment_min_balance != null and !parsed.tx_build_auto_gas_payment) return error.InvalidCli;
        const kind = parsed.tx_build_kind orelse return error.InvalidCli;
        switch (kind) {
            .move_call => {
                if (parsed.tx_build_commands != null or hasCommandItems(&parsed)) return error.InvalidCli;
                if (!hasCompleteMoveCallArgs(&parsed)) return error.InvalidCli;
            },
            .programmable => {
                if (hasMoveCallArgs(&parsed)) return error.InvalidCli;
                if (parsed.tx_build_commands == null and !hasCommandItems(&parsed)) return error.InvalidCli;
            },
        }
        if (parsed.tx_session_response != null and !parsed.tx_build_emit_tx_block) return error.InvalidCli;
        if (parsed.tx_provider_config != null and !parsed.tx_build_emit_tx_block) return error.InvalidCli;
    }

    if (parsed.tx_session_response != null and parsed.tx_provider_config == null) return error.InvalidCli;

    if (parsed.command == .move_package and parsed.move_package == null) return error.InvalidCli;
    if (parsed.command == .move_module) {
        if (parsed.move_package == null or parsed.move_module == null) return error.InvalidCli;
    }
    if (parsed.command == .move_function) {
        if (parsed.move_package == null or parsed.move_module == null or parsed.move_function == null) return error.InvalidCli;
        if (parsed.move_function_execute_dry_run and parsed.move_function_execute_send) return error.InvalidCli;
        if (parsed.move_function_template_output != null and
            (parsed.move_function_execute_dry_run or parsed.move_function_execute_send))
        {
            return error.InvalidCli;
        }
        if (parsed.tx_send_wait and !parsed.move_function_execute_send) return error.InvalidCli;
        if (parsed.tx_send_observe and !parsed.move_function_execute_send) return error.InvalidCli;
        if (parsed.tx_send_summarize and parsed.tx_send_observe) return error.InvalidCli;
        if (parsed.tx_provider_config != null and
            !(parsed.move_function_execute_dry_run or parsed.move_function_execute_send))
        {
            return error.InvalidCli;
        }
        if (parsed.tx_session_response != null and
            !(parsed.move_function_execute_dry_run or parsed.move_function_execute_send))
        {
            return error.InvalidCli;
        }
    }

    if (parsed.command == .object_get and parsed.object_id == null) return error.InvalidCli;
    if ((parsed.command == .object_get or parsed.command == .account_objects or parsed.command == .wallet_objects or parsed.command == .account_resources) and
        parsed.object_options != null and
        (parsed.object_show_type or
            parsed.object_show_owner or
            parsed.object_show_previous_transaction or
            parsed.object_show_display or
            parsed.object_show_content or
            parsed.object_show_bcs or
            parsed.object_show_storage_rebate))
    {
        return error.InvalidCli;
    }
    if (parsed.command == .object_dynamic_fields) {
        if (parsed.object_parent_id == null) return error.InvalidCli;
        if (parsed.object_dynamic_fields_all and parsed.object_dynamic_fields_cursor != null) return error.InvalidCli;
    }
    if (parsed.command == .account_coins) {
        if (parsed.account_selector == null) return error.InvalidCli;
        if (parsed.account_coins_all and parsed.account_coins_cursor != null) return error.InvalidCli;
    }
    if (parsed.command == .account_objects) {
        if (parsed.account_selector == null) return error.InvalidCli;
        if (parsed.account_objects_all and parsed.account_objects_cursor != null) return error.InvalidCli;
        const has_raw_filter = parsed.account_objects_filter != null;
        const has_struct_filter = parsed.account_objects_struct_type != null;
        const has_object_id_filter = parsed.account_objects_object_id != null;
        const has_package_filter = parsed.account_objects_package != null;
        const has_module_filter = parsed.account_objects_module != null;
        if (has_raw_filter and (has_struct_filter or has_object_id_filter or has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_struct_filter and (has_object_id_filter or has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_object_id_filter and (has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_module_filter and !has_package_filter) return error.InvalidCli;
    }
    if (parsed.command == .account_resources) {
        if (parsed.account_selector == null) return error.InvalidCli;
        const has_raw_filter = parsed.account_objects_filter != null;
        const has_struct_filter = parsed.account_objects_struct_type != null;
        const has_object_id_filter = parsed.account_objects_object_id != null;
        const has_package_filter = parsed.account_objects_package != null;
        const has_module_filter = parsed.account_objects_module != null;
        if (has_raw_filter and (has_struct_filter or has_object_id_filter or has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_struct_filter and (has_object_id_filter or has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_object_id_filter and (has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_module_filter and !has_package_filter) return error.InvalidCli;
    }
    if (parsed.command == .wallet_address) {
        if (parsed.account_selector) |selector| {
            if (selector.len == 0) return error.InvalidCli;
        }
    }
    if (parsed.command == .wallet_create or parsed.command == .wallet_import) {
        if (parsed.wallet_alias) |alias| {
            if (alias.len == 0) return error.InvalidCli;
        }
    }
    if (parsed.command == .wallet_import) {
        const raw_key = parsed.wallet_private_key orelse return error.InvalidCli;
        if (std.mem.trim(u8, raw_key, " \n\r\t").len == 0) return error.InvalidCli;
    }
    if (parsed.command == .wallet_use) {
        const selector = parsed.account_selector orelse return error.InvalidCli;
        if (selector.len == 0) return error.InvalidCli;
    }
    if (parsed.command == .wallet_export_public or parsed.command == .wallet_signer_inspect) {
        if (parsed.account_selector) |selector| {
            if (selector.len == 0) return error.InvalidCli;
        }
    }
    if (parsed.command == .wallet_balance) {
        if (parsed.account_selector) |selector| {
            if (selector.len == 0) return error.InvalidCli;
        }
    }
    if (parsed.command == .wallet_coins) {
        if (parsed.account_selector) |selector| {
            if (selector.len == 0) return error.InvalidCli;
        }
        if (parsed.account_coins_all and parsed.account_coins_cursor != null) return error.InvalidCli;
    }
    if (parsed.command == .wallet_objects) {
        if (parsed.account_selector) |selector| {
            if (selector.len == 0) return error.InvalidCli;
        }
        if (parsed.account_objects_all and parsed.account_objects_cursor != null) return error.InvalidCli;
        const has_raw_filter = parsed.account_objects_filter != null;
        const has_struct_filter = parsed.account_objects_struct_type != null;
        const has_object_id_filter = parsed.account_objects_object_id != null;
        const has_package_filter = parsed.account_objects_package != null;
        const has_module_filter = parsed.account_objects_module != null;
        if (has_raw_filter and (has_struct_filter or has_object_id_filter or has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_struct_filter and (has_object_id_filter or has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_object_id_filter and (has_package_filter or has_module_filter)) return error.InvalidCli;
        if (has_module_filter and !has_package_filter) return error.InvalidCli;
    }
    if (parsed.command == .request_status) {
        const digest = parsed.tx_digest orelse return error.InvalidCli;
        if (digest.len == 0) return error.InvalidCli;
    }
    if (parsed.command == .request_cancel or parsed.command == .request_resume) {
        const entry_id = parsed.request_entry_id orelse return error.InvalidCli;
        if (entry_id.len == 0) return error.InvalidCli;
    }
    if (parsed.command == .request_sponsor or parsed.command == .request_schedule) {
        if (parsed.request_valid_after_ms != null and parsed.request_valid_before_ms != null and
            parsed.request_valid_after_ms.? > parsed.request_valid_before_ms.?)
        {
            return error.InvalidCli;
        }
        if (parsed.request_sponsor_mode) |mode| {
            if (!(std.mem.eql(u8, mode, "direct") or std.mem.eql(u8, mode, "optional") or std.mem.eql(u8, mode, "required"))) {
                return error.InvalidCli;
            }
        }
        if (parsed.request_correlation_id) |value| {
            if (value.len == 0) return error.InvalidCli;
        }
    }
    if (parsed.command == .request_schedule) {
        if (parsed.request_schedule_at_ms == null and parsed.request_valid_after_ms == null and parsed.request_valid_before_ms == null) {
            return error.InvalidCli;
        }
        if (parsed.request_schedule_id) |value| {
            if (value.len == 0) return error.InvalidCli;
        }
        if (parsed.request_schedule_replace_id) |value| {
            if (value.len == 0) return error.InvalidCli;
        }
    }
    if (parsed.command == .events) {
        const has_raw_filter = parsed.event_filter != null;
        const has_module_filter = parsed.event_package != null or parsed.event_module != null;
        const has_type_filter = parsed.event_type != null;
        const has_sender_filter = parsed.event_sender != null;
        const has_tx_filter = parsed.event_tx_digest_filter != null;
        const typed_filter_count: u8 =
            @intFromBool(has_module_filter) +
            @intFromBool(has_type_filter) +
            @intFromBool(has_sender_filter) +
            @intFromBool(has_tx_filter);
        if (has_raw_filter and typed_filter_count != 0) return error.InvalidCli;
        if (parsed.event_module != null and parsed.event_package == null) return error.InvalidCli;
        if (parsed.event_package != null and parsed.event_module == null) return error.InvalidCli;
        if (typed_filter_count > 1) return error.InvalidCli;
        if ((parsed.event_cursor_tx_digest == null) != (parsed.event_cursor_event_seq == null)) return error.InvalidCli;
    }
    if (parsed.command == .object_dynamic_field_object) {
        if (parsed.object_parent_id == null) return error.InvalidCli;
        const has_raw_name = parsed.object_dynamic_field_name != null;
        const has_typed_name = parsed.object_dynamic_field_name_type != null or parsed.object_dynamic_field_name_value != null;
        if (has_raw_name == has_typed_name) return error.InvalidCli;
        if (has_typed_name and (parsed.object_dynamic_field_name_type == null or parsed.object_dynamic_field_name_value == null)) {
            return error.InvalidCli;
        }
    }

    parsed_ok = true;
    return parsed;
}

pub fn printUsage(writer: anytype) !void {
    try writer.print("Usage: sui-zig-rpc-client [global options] <command> [options]\n\n" ++
        "Commands:\n" ++
        "  help                                Show this help\n" ++
        "  version                             Print version\n" ++
        "  rpc <method> [params-json]          Send a raw JSON-RPC request\n" ++
        "  events                              Call suix_queryEvents\n" ++
        "    --filter <json|@file>               Raw event filter JSON\n" ++
        "    --package <package-id-or-alias> --module <module>\n" ++
        "                                       Typed MoveModule event filter\n" ++
        "    --event-type <type>                 Typed MoveEventType filter\n" ++
        "    --sender <address>                  Typed Sender filter\n" ++
        "    --tx <digest>                       Typed Transaction filter\n" ++
        "    --cursor-tx <digest> --cursor-event <seq>\n" ++
        "                                       Pagination cursor\n" ++
        "    --limit <n>                         Page size\n" ++
        "    --descending                        Query newest events first\n" ++
        "    --all                               Aggregate all pages\n" ++
        "    --json                              Emit raw RPC JSON instead of summarized output\n" ++
        "  move package <package-id-or-alias>  Call sui_getNormalizedMoveModulesByPackage\n" ++
        "    --summarize                         Print module counts instead of raw normalized JSON\n" ++
        "  move module <package-id-or-alias> <module>\n" ++
        "                                       Call sui_getNormalizedMoveModule\n" ++
        "    --summarize                         Print struct/function inventory instead of raw normalized JSON\n" ++
        "  move function <package-id-or-alias> <module> <function>\n" ++
        "                                       Call sui_getNormalizedMoveFunction\n" ++
        "    --type-args <json|@file>            Optional JSON array to specialize generic type parameters locally\n" ++
        "    --type-arg <type>                   Repeatable Move type argument shorthand for --type-args\n" ++
        "    --args <json|@file>                 Optional explicit argument JSON used to specialize preferred templates\n" ++
        "    --arg <json|bare|@file>             Repeatable explicit argument shorthand for --args\n" ++
        "    --arg-at <index> <json|bare|@file>  Repeatable explicit argument override by parameter index\n" ++
        "    --object-arg-at <index> <object>    Repeatable object-id-or-alias or JSON string array override by parameter index\n" ++
        "    --emit-template <kind>              Print one generated template directly: commands|preferred-commands|dry-run-request|preferred-dry-run-request|send-request|preferred-send-request\n" ++
        "    --dry-run                           Resolve the preferred dry-run request artifact and execute it immediately\n" ++
        "    --send                              Resolve the preferred send request artifact and execute it immediately\n" ++
        "    --sender <address|selector>         Optional owner context for discovery hints and tx templates\n" ++
        "    --signer <alias|address|key>        Optional signer selector; first address-compatible signer becomes owner context\n" ++
        "    --from-keystore                     Use the first default keystore address as owner context when needed\n" ++
        "    --provider <json|@file>             Standalone session-backed provider config for --dry-run/--send\n" ++
        "    --session-response <json|@file>     Apply a previously approved provider session response for --dry-run/--send\n" ++
        "    --wait|--observe                    Forward send execution mode when used with --send\n" ++
        "    --summarize                         Print parameter/return signature summary, lowering hints, discovery hints, and tx call templates\n" ++
        "  object get <object-id-or-alias>      Call sui_getObject\n" ++
        "    --options <json|@file>              object read options\n" ++
        "    --show-type|--show-owner|--show-content|--show-bcs\n" ++
        "    --show-display|--show-storage-rebate|--show-previous-transaction\n" ++
        "                                       typed object read options; do not mix with --options\n" ++
        "    --summarize                         Print structured object summary instead of raw response\n" ++
        "  object dynamic-fields <object-id-or-alias>\n" ++
        "                                       Call suix_getDynamicFields\n" ++
        "    --cursor <cursor>                   pagination cursor\n" ++
        "    --limit <n>                         page size\n" ++
        "    --all                               aggregate all pages and print structured results\n" ++
        "    --summarize                         Print structured page summary for a single page\n" ++
        "  object dynamic-field-object <object-id-or-alias> <name-json|@file>\n" ++
        "                                       Call suix_getDynamicFieldObject\n" ++
        "    --name-type <type> --name-value <json|@file>\n" ++
        "                                       typed dynamic-field name input; do not mix with positional name-json\n" ++
        "    --summarize                         Print structured object summary instead of raw response\n" ++
        "  tx build move-call                    Build move-call transaction instruction\n" ++
        "  tx build programmable [options]        Build arbitrary programmable transaction block\n" ++
        "    --package <package-id-or-alias>     Move package id\n" ++
        "    --module <module-name>              Move module name\n" ++
        "    --function <function-name>          Move function name\n" ++
        "    --type-args <json|@file>            Optional JSON array\n" ++
        "    --type-arg <type>                   Repeatable Move type argument\n" ++
        "    --args <json|@file>                 Optional JSON array\n" ++
        "    --arg <json|bare|@file>             Repeatable Move argument; bare values become JSON strings\n" ++
        "    --sender <address|selector>         Optional sender address or keystore selector/index\n" ++
        "    --signer <alias|address|key>         Optional signer selector/index; first address-compatible signer is used as sender\n" ++
        "    --commands <json-array|@file>        JSON array of command objects\n" ++
        "    --command <json-array|json-object|@file> (repeatable) command fragment\n" ++
        "    --move-call <package> <module> <function> [<type-args-json|@file> <args-json|@file>]\n" ++
        "    --move-call-type-arg <type>         Repeatable typed command MoveCall type argument\n" ++
        "    --move-call-arg <json|bare|@file>   Repeatable typed command MoveCall argument\n" ++
        "    --summarize                         Print structured build-artifact summary instead of raw JSON\n" ++
        "    --transfer-objects [<objects-json|@file> <address-json|@file>] append TransferObjects command\n" ++
        "    --transfer-object <json|bare|@file> repeatable TransferObjects input object\n" ++
        "    --transfer-address <json|bare|@file> TransferObjects destination value\n" ++
        "    --split-coins [<coin-json|@file> <amounts-json|@file>]        append SplitCoins command\n" ++
        "    --split-coin <json|bare|@file>     SplitCoins source coin value\n" ++
        "    --split-amount <json|bare|@file>   repeatable SplitCoins amount\n" ++
        "    --merge-coins [<destination-json|@file> <sources-json|@file>] append MergeCoins command\n" ++
        "    --merge-destination <json|bare|@file> MergeCoins destination value\n" ++
        "    --merge-source <json|bare|@file>   repeatable MergeCoins source\n" ++
        "    --gas-budget <gas>                 Optional gas budget\n" ++
        "    --gas-price <gas>                  Optional gas price\n" ++
        "    --emit-tx-block                    Build programmable transaction block JSON\n" ++
        "    --provider <json|@file>           Standalone session-backed provider config for tx-block builds\n" ++
        "    --session-response <json|@file>   Apply a previously approved provider session response\n" ++
        "    typed arg tokens: @0x... addr:0x... obj:0x... bytes:0x... bool:true u64:7 u128:... ptb:name:<alias>[:idx]\n" ++
        "                      <alias>[.<idx>] vec:[...] vector[...] option:some:<json> some(...) option:none\n" ++
        "    selected request tokens: select:{{\"kind\":\"owned_object_struct_type\",...}} select:{{\"kind\":\"coin_with_min_balance\",...}} select:{{\"kind\":\"object_preset\",\"name\":\"clock\"}} select:{{\"kind\":\"object_input\",\"objectId\":\"0x...\",\"inputKind\":\"shared\",\"mutable\":true,\"initialSharedVersion\":1}}\n" ++
        "                      bare values still fall back to string/JSON parsing\n" ++
        "  wallet create                       Generate a new local keystore wallet entry\n" ++
        "    --alias <name>                    Optional alias stored with the entry\n" ++
        "    --no-activate                     Leave the current active wallet selector unchanged\n" ++
        "    --json                            Emit machine-readable wallet metadata\n" ++
        "  wallet import <private-key>         Import a raw Sui private key into the local keystore\n" ++
        "    --private-key <value|@file>       Optional file-backed form of the same input\n" ++
        "    --alias <name>                    Optional alias stored with the entry\n" ++
        "    --no-activate                     Leave the current active wallet selector unchanged\n" ++
        "    --json                            Emit machine-readable wallet metadata\n" ++
        "  wallet use <selector|0xaddress>     Set the active wallet selector for wallet commands\n" ++
        "    --json                            Emit machine-readable wallet metadata\n" ++
        "  wallet export-public [selector]     Export public wallet metadata without private keys\n" ++
        "    --json                            Emit machine-readable export metadata\n" ++
        "  wallet signer inspect [selector]    Inspect signer resolution for a wallet selector or active wallet\n" ++
        "    --json                            Emit machine-readable signer metadata\n" ++
        "  wallet address [selector]           Print the resolved wallet address\n" ++
        "  wallet balance [selector]           Print aggregated coin balances for a wallet\n" ++
        "    --coin-type <type>                 Optional coin type filter\n" ++
        "    --limit <n>                        Page size used while aggregating balances\n" ++
        "    --all                              Aggregate all coin pages instead of a single page\n" ++
        "  wallet coins [selector]             Query wallet-owned coin objects with default-wallet fallback\n" ++
        "    same options as account coins, including --json/--coin-type/--cursor/--limit/--all\n" ++
        "  wallet objects [selector]           Query wallet-owned objects with default-wallet fallback\n" ++
        "    same options as account objects, including typed filters and --json\n" ++
        "  wallet intent build                 Build a first-class wallet intent envelope around a request artifact\n" ++
        "    same input options as request build plus --intent/--network/--execution-mode/--policy\n" ++
        "  wallet intent dry-run               Dry-run a wallet intent or request-shaped tx input\n" ++
        "    same input options as request dry-run plus --intent/--network/--execution-mode/--policy\n" ++
        "  wallet intent send                  Send a wallet intent or request-shaped tx input\n" ++
        "    same input options as request send plus --intent/--network/--execution-mode/--policy\n" ++
        "  request build                       Build a normalized request artifact from programmatic tx input\n" ++
        "    --request <json|@file>             Normalize an existing request artifact\n" ++
        "    --package/--module/--function      Build from move-call input\n" ++
        "    --commands/--command               Build from programmable command input\n" ++
        "    --sender <address|selector>        Optional sender; selectors resolve through the default keystore\n" ++
        "    --gas-budget/--gas-price           Optional gas settings\n" ++
        "    --gas-payment <json|@file>         Optional gas payment JSON\n" ++
        "    --auto-gas-payment|--auto-gas-budget\n" ++
        "    --gas-payment-min-balance <amount> Optional auto gas minimum balance\n" ++
        "    --options <json|@file>             Optional request options JSON\n" ++
        "    --signer <alias|address|key>       Optional signer selector used to infer sender\n" ++
        "    --from-keystore                    Infer sender from the default keystore when needed\n" ++
        "  request inspect                     Print a structured summary of a request artifact\n" ++
        "    same input options as request build\n" ++
        "  request dry-run                     Dry-run a request artifact or request-shaped tx input\n" ++
        "    same input options as request build\n" ++
        "    --summarize                        Print structured dry-run summary instead of raw response\n" ++
        "  request sponsor                     Wrap a request artifact in a sponsor-ready envelope\n" ++
        "    same input options as request build\n" ++
        "    --sponsor-mode <direct|optional|required>\n" ++
        "    --sponsor-policy <json|@file>     Optional sponsor policy metadata JSON\n" ++
        "    --valid-after-ms/--valid-before-ms Optional validity window metadata\n" ++
        "    --correlation-id <text>           Optional replay/correlation id\n" ++
        "  request sign                        Attach signer/provider approvals and print an execute payload\n" ++
        "    same input options as request build plus tx-payload signer/provider flags\n" ++
        "    --summarize                        Print structured execute-payload summary instead of raw payload\n" ++
        "  request send                        Send a request artifact or request-shaped tx input\n" ++
        "    same input options as request build plus tx-send signer/provider flags\n" ++
        "    --wait/--summarize/--observe       Reuse tx send confirmation and output modes\n" ++
        "  request schedule                    Wrap a request artifact in a scheduler-friendly job envelope\n" ++
        "    same input options as request sponsor\n" ++
        "    --schedule-at-ms <unix-ms>        Desired execution time\n" ++
        "    --schedule-id <text>              Optional scheduler job id\n" ++
        "    --replace-schedule-id <text>      Optional previous job id to replace\n" ++
        "  request list                        List locally tracked request and schedule entries\n" ++
        "  request cancel <id>                 Mark a locally tracked scheduled request as cancelled\n" ++
        "  request resume <id>                 Return a locally tracked scheduled request to scheduled state\n" ++
        "  request rebroadcast <id>            Re-send a locally tracked request through the standard request send path\n" ++
        "    same signer/provider output flags as request send\n" ++
        "  request status <digest>             Query the execution status of a previously sent request\n" ++
        "    same options as tx status, including --summarize/--observe/--poll-ms/--confirm-timeout-ms\n" ++
        "  account list                        List local keystore accounts\n" ++
        "  tx simulate [params-json]            Call sui_devInspectTransactionBlock\n" ++
        "    --package <package-id-or-alias>     Move package id\n" ++
        "    --module <module-name>              Move module name\n" ++
        "    --function <function-name>          Move function name\n" ++
        "    --type-args <json|@file>            Optional JSON array\n" ++
        "    --type-arg <type>                   Repeatable Move type argument\n" ++
        "    --args <json|@file>                 Optional JSON array\n" ++
        "    --arg <json|bare|@file>             Repeatable Move argument; bare values become JSON strings\n" ++
        "    --commands <json-array|@file>        JSON array for programmable transaction commands\n" ++
        "    --command <json-array|json-object|@file> (repeatable) command fragment\n" ++
        "    --move-call <package> <module> <function> [<type-args-json|@file> <args-json|@file>]\n" ++
        "    --move-call-type-arg <type>         Repeatable typed command MoveCall type argument\n" ++
        "    --move-call-arg <json|bare|@file>   Repeatable typed command MoveCall argument\n" ++
        "    --transfer-objects [<objects-json|@file> <address-json|@file>] append TransferObjects command\n" ++
        "    --transfer-object <json|bare|@file> repeatable TransferObjects input object\n" ++
        "    --transfer-address <json|bare|@file> TransferObjects destination value\n" ++
        "    --split-coins [<coin-json|@file> <amounts-json|@file>]        append SplitCoins command\n" ++
        "    --split-coin <json|bare|@file>     SplitCoins source coin value\n" ++
        "    --split-amount <json|bare|@file>   repeatable SplitCoins amount\n" ++
        "    --merge-coins [<destination-json|@file> <sources-json|@file>] append MergeCoins command\n" ++
        "    --merge-destination <json|bare|@file> MergeCoins destination value\n" ++
        "    --merge-source <json|bare|@file>   repeatable MergeCoins source\n" ++
        "    --sender <address|selector>         Optional sender address or keystore selector/index\n" ++
        "    --gas-budget <gas>                 Optional gas budget\n" ++
        "    --gas-price <gas>                  Optional gas price\n" ++
        "    --signer <name|address|key>         Optional signer selector/index; first address-compatible signer is used as sender\n" ++
        "    --provider <json|@file>             Standalone session-backed provider config\n" ++
        "    --session-response <json|@file>     Apply a previously approved provider session response\n" ++
        "    --options <json|@file>              optional inspect options\n" ++
        "  tx dry-run [tx-bytes|@file]          Call sui_dryRunTransactionBlock\n" ++
        "    --tx-bytes <base64|@file>           Prebuilt tx bytes for dry-run\n" ++
        "    --request <json|@file>              Programmatic request artifact with commands/sender/gas fields\n" ++
        "    --package <package-id-or-alias>     Move package id\n" ++
        "    --module <module-name>              Move module name\n" ++
        "    --function <function-name>          Move function name\n" ++
        "    --type-args <json|@file>            Optional JSON array\n" ++
        "    --type-arg <type>                   Repeatable Move type argument\n" ++
        "    --args <json|@file>                 Optional JSON array\n" ++
        "    --arg <json|bare|@file>             Repeatable Move argument; bare values become JSON strings\n" ++
        "    --commands <json-array|@file>        JSON array for programmable transaction commands\n" ++
        "    --command <json-array|json-object|@file> (repeatable) command fragment\n" ++
        "    --move-call <package> <module> <function> [<type-args-json|@file> <args-json|@file>]\n" ++
        "    --move-call-type-arg <type>         Repeatable typed command MoveCall type argument\n" ++
        "    --move-call-arg <json|bare|@file>   Repeatable typed command MoveCall argument\n" ++
        "    --transfer-objects [<objects-json|@file> <address-json|@file>] append TransferObjects command\n" ++
        "    --transfer-object <json|bare|@file> repeatable TransferObjects input object\n" ++
        "    --transfer-address <json|bare|@file> TransferObjects destination value\n" ++
        "    --split-coins [<coin-json|@file> <amounts-json|@file>]        append SplitCoins command\n" ++
        "    --split-coin <json|bare|@file>     SplitCoins source coin value\n" ++
        "    --split-amount <json|bare|@file>   repeatable SplitCoins amount\n" ++
        "    --merge-coins [<destination-json|@file> <sources-json|@file>] append MergeCoins command\n" ++
        "    --merge-destination <json|bare|@file> MergeCoins destination value\n" ++
        "    --merge-source <json|bare|@file>   repeatable MergeCoins source\n" ++
        "    --sender <address|selector>         Optional sender address or keystore selector/index\n" ++
        "    --signer <name|address|key>         Optional signer selector/index; first address-compatible signer is used as sender\n" ++
        "    --from-keystore                     Infer sender from the first default keystore entry when needed\n" ++
        "    --gas-budget <gas>                  Optional gas budget\n" ++
        "    --gas-price <gas>                   Optional gas price\n" ++
        "    --gas-payment <json|@file>          Optional gas payment JSON\n" ++
        "    --auto-gas-payment                  Select gas payment automatically\n" ++
        "    --gas-payment-min-balance <amount>  Minimum balance for auto gas selection\n" ++
        "    --summarize                         Print structured dry-run summary instead of raw response\n" ++
        "  tx send [params-json]                Call sui_executeTransactionBlock\n" ++
        "    --request <json|@file>              Programmatic request artifact with commands/provider fields\n" ++
        "    --package <package-id-or-alias>     Move package id\n" ++
        "    --module <module-name>              Move module name\n" ++
        "    --function <function-name>          Move function name\n" ++
        "    --type-args <json|@file>            Optional JSON array\n" ++
        "    --type-arg <type>                   Repeatable Move type argument\n" ++
        "    --args <json|@file>                 Optional JSON array\n" ++
        "    --arg <json|bare|@file>             Repeatable Move argument; bare values become JSON strings\n" ++
        "    --commands <json-array|@file>        JSON array for programmable transaction commands\n" ++
        "    --command <json-array|json-object|@file> (repeatable) command fragment\n" ++
        "    --move-call <package> <module> <function> [<type-args-json|@file> <args-json|@file>]\n" ++
        "    --move-call-type-arg <type>         Repeatable typed command MoveCall type argument\n" ++
        "    --move-call-arg <json|bare|@file>   Repeatable typed command MoveCall argument\n" ++
        "    --transfer-objects [<objects-json|@file> <address-json|@file>] append TransferObjects command\n" ++
        "    --transfer-object <json|bare|@file> repeatable TransferObjects input object\n" ++
        "    --transfer-address <json|bare|@file> TransferObjects destination value\n" ++
        "    --split-coins [<coin-json|@file> <amounts-json|@file>]        append SplitCoins command\n" ++
        "    --split-coin <json|bare|@file>     SplitCoins source coin value\n" ++
        "    --split-amount <json|bare|@file>   repeatable SplitCoins amount\n" ++
        "    --merge-coins [<destination-json|@file> <sources-json|@file>] append MergeCoins command\n" ++
        "    --merge-destination <json|bare|@file> MergeCoins destination value\n" ++
        "    --merge-source <json|bare|@file>   repeatable MergeCoins source\n" ++
        "    --sender <address|selector>         Optional sender address or keystore selector/index\n" ++
        "    --gas-budget <gas>                  Optional gas budget\n" ++
        "    --gas-price <gas>                   Optional gas price\n" ++
        "    --signature <sig>                   (repeatable) signatures list\n" ++
        "    --signature-file <path>                  Load signature from file\n" ++
        "    --signer <name|address|key>         Select key from keystore\n" ++
        "    --from-keystore                     Append first key from keystore when signatures are missing\n" ++
        "    --provider <json|@file>             Standalone session-backed provider config\n" ++
        "    --session-response <json|@file>     Apply a previously approved provider session response\n" ++
        "    --options <json|@file>              optional execute options\n" ++
        "  tx payload                           Build execute params from tx bytes/signatures/options\n" ++
        "    --tx-bytes <base64>                 (required) tx_bytes input\n" ++
        "    --package <package-id-or-alias>     Move package id\n" ++
        "    --module <module-name>              Move module name\n" ++
        "    --function <function-name>          Move function name\n" ++
        "    --type-args <json|@file>            Optional JSON array\n" ++
        "    --type-arg <type>                   Repeatable Move type argument\n" ++
        "    --args <json|@file>                 Optional JSON array\n" ++
        "    --arg <json|bare|@file>             Repeatable Move argument; bare values become JSON strings\n" ++
        "    --commands <json-array|@file>        JSON array for programmable transaction commands\n" ++
        "    --command <json-array|json-object|@file> (repeatable) command fragment\n" ++
        "    --move-call <package> <module> <function> [<type-args-json|@file> <args-json|@file>]\n" ++
        "    --move-call-type-arg <type>         Repeatable typed command MoveCall type argument\n" ++
        "    --move-call-arg <json|bare|@file>   Repeatable typed command MoveCall argument\n" ++
        "    --transfer-objects [<objects-json|@file> <address-json|@file>] append TransferObjects command\n" ++
        "    --transfer-object <json|bare|@file> repeatable TransferObjects input object\n" ++
        "    --transfer-address <json|bare|@file> TransferObjects destination value\n" ++
        "    --split-coins [<coin-json|@file> <amounts-json|@file>]        append SplitCoins command\n" ++
        "    --split-coin <json|bare|@file>     SplitCoins source coin value\n" ++
        "    --split-amount <json|bare|@file>   repeatable SplitCoins amount\n" ++
        "    --merge-coins [<destination-json|@file> <sources-json|@file>] append MergeCoins command\n" ++
        "    --merge-destination <json|bare|@file> MergeCoins destination value\n" ++
        "    --merge-source <json|bare|@file>   repeatable MergeCoins source\n" ++
        "    --sender <address|selector>         Optional sender address or keystore selector/index\n" ++
        "    --gas-budget <gas>                  Optional gas budget\n" ++
        "    --gas-price <gas>                   Optional gas price\n" ++
        "    --signature <sig>                   (repeatable) signatures list\n" ++
        "    --signature-file <path>                  Load signature from file\n" ++
        "    --signer <name|address|key>         Select key from keystore\n" ++
        "    --from-keystore                     Append first key from keystore when signatures are missing\n" ++
        "    --provider <json|@file>             Standalone session-backed provider config\n" ++
        "    --session-response <json|@file>     Apply a previously approved provider session response\n" ++
        "    --summarize                         Print structured execute-payload summary instead of raw payload\n" ++
        "    --options <json|@file>              optional execute options\n" ++
        "  tx status <digest>                   Query sui_getTransactionBlock once\n" ++
        "    --summarize                         Print structured execution summary instead of raw response\n" ++
        "    --observe                           Print digest + confirmed response + summary\n" ++
        "  tx confirm|wait <digest>             Poll sui_getTransactionBlock until found\n" ++
        "    --summarize                         Print structured execution summary instead of raw response\n" ++
        "    --observe                           Print digest + confirmed response + summary\n" ++
        "  account list                         List local keystore accounts\n" ++
        "    --json                               Emit machine-readable account JSON\n" ++
        "  account info <selector>               Show keystore entry by selector/index\n" ++
        "    --json                               Emit machine-readable account JSON\n" ++
        "  account coins <selector|0xaddress>    List coins for a local selector or address\n" ++
        "    --coin-type <type>                    Filter by coin type\n" ++
        "    --cursor <cursor>                     Page from a specific cursor\n" ++
        "    --limit <n>                           Page size\n" ++
        "    --all                                 Aggregate all pages\n" ++
        "    --json                                Emit raw RPC JSON instead of summarized output\n" ++
        "  account objects <selector|0xaddress>  List owned objects for a local selector or address\n" ++
        "    --filter <json|@file>                 Optional Sui object filter\n" ++
        "    --struct-type <type>                  Typed filter: StructType\n" ++
        "    --object-id <id>                      Typed filter: ObjectId\n" ++
        "    --package <package-id-or-alias>       Typed filter: Package\n" ++
        "    --module <module-name>                Typed filter: MoveModule (requires --package)\n" ++
        "    --options <json|@file>                Optional object data options\n" ++
        "    --show-type                           Typed option: include object type\n" ++
        "    --show-owner                          Typed option: include owner\n" ++
        "    --show-previous-transaction           Typed option: include previous transaction\n" ++
        "    --show-display                        Typed option: include display\n" ++
        "    --show-content                        Typed option: include content\n" ++
        "    --show-bcs                            Typed option: include BCS\n" ++
        "    --show-storage-rebate                 Typed option: include storage rebate\n" ++
        "    --cursor <cursor>                     Page from a specific cursor\n" ++
        "    --limit <n>                           Page size\n" ++
        "    --all                                 Aggregate all pages\n" ++
        "    --json                                Emit raw RPC JSON instead of summarized output\n" ++
        "  account resources <selector|0xaddress> List coins and owned objects for a local selector or address\n" ++
        "    --coin-type <type>                    Filter coin discovery by coin type\n" ++
        "    --filter <json|@file>                 Optional owned-object filter\n" ++
        "    --struct-type <type>                  Typed owned-object StructType filter\n" ++
        "    --object-id <id>                      Typed owned-object ObjectId filter\n" ++
        "    --package <package-id-or-alias>       Typed owned-object Package filter\n" ++
        "    --module <module-name>                Typed owned-object MoveModule filter (requires --package)\n" ++
        "    --options <json|@file>                Optional owned-object data options\n" ++
        "    --show-type                           Typed option: include object type\n" ++
        "    --show-owner                          Typed option: include owner\n" ++
        "    --show-previous-transaction           Typed option: include previous transaction\n" ++
        "    --show-display                        Typed option: include display\n" ++
        "    --show-content                        Typed option: include content\n" ++
        "    --show-bcs                            Typed option: include BCS\n" ++
        "    --show-storage-rebate                 Typed option: include storage rebate\n" ++
        "    --limit <n>                           Shared page size for coins and owned objects\n" ++
        "    --all                                 Aggregate all pages for both resources\n" ++
        "    --json                                Emit raw combined JSON instead of summarized output\n\n" ++
        "Global options:\n" ++
        "  --rpc <url>                          RPC endpoint (default: {s})\n" ++
        "                                       Environment precedence: --rpc > SUI_RPC_URL > SUI_CONFIG\n" ++
        "  SUI_RPC_URL=<url>                    Override rpc endpoint when --rpc is not provided\n" ++
        "  --timeout-ms <ms>                    HTTP request timeout\n" ++
        "  --confirm-timeout-ms <ms>             Confirm timeout\n" ++
        "  --poll-ms <ms>                       Polling interval for tx confirm\n" ++
        "  --pretty                             Pretty-print response JSON\n" ++
        "  @-                                   For any file-backed arg, read the value from stdin\n" ++
        "  SUI_CONFIG=<path>                    Path to config file (default: ~/.sui/sui_config/client.yaml)\n" ++
        "                                       Supports rpc_url/json_rpc_url and Sui yaml envs format\n" ++
        "  SUI_KEYSTORE=<path>                  Path to keystore file (default: ~/.sui/sui_config/sui.keystore)\n" ++
        "  --help, -h                           Show this usage\n" ++
        "  --version                            Print version\n", .{default_rpc_url});
}

test "parseCliArgs default usage with empty args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{};
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expect(parsed.show_usage);
    try testing.expectEqual(Command.help, parsed.command);
}

test "parseCliArgs parses global options and tx_send tx-bytes mode" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "--rpc",
        "https://example-rpc.test",
        "--pretty",
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--signature",
        "sig-one",
        "--sig",
        "sig-two",
        "--options",
        "{\"gasBudget\":1234}",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expect(parsed.pretty);
    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings("https://example-rpc.test", parsed.rpc_url);
    try testing.expectEqualStrings("dGVzdF90eF9ieXRlcw==", parsed.tx_bytes.?);
    try testing.expectEqual(@as(usize, 2), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-one", parsed.signatures.items[0]);
    try testing.expectEqualStrings("sig-two", parsed.signatures.items[1]);
    try testing.expectEqualStrings("{\"gasBudget\":1234}", parsed.tx_options.?);
    try testing.expect(!parsed.from_keystore);
    try testing.expectEqual(@as(usize, 0), parsed.signers.items.len);
}

test "parseCliArgs maps tx_send --params file to tx-bytes input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    const params_file = "tmp_cli_tx_send_params.json";
    try cwd.writeFile(.{ .sub_path = params_file, .data = "dGVzdF90eF9ieXRlcw==" });
    defer cwd.deleteFile(params_file) catch {};

    const params_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{params_file});
    defer allocator.free(params_file_arg);

    const args = [_][]const u8{
        "tx",
        "send",
        "--params",
        params_file_arg,
        "--signature",
        "sig-a",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings("dGVzdF90eF9ieXRlcw==", parsed.tx_bytes.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
}

test "parseCliArgs parses tx_send positional params as tx-bytes input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "dGVzdF90eF9ieXRlcw==",
        "--signature",
        "sig-a",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings("dGVzdF90eF9ieXRlcw==", parsed.tx_bytes.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
}

test "parseCliArgs maps tx_send --params to tx-bytes input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--params",
        "dGVzdF90eF9ieXRlcw==",
        "--signature",
        "sig-a",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings("dGVzdF90eF9ieXRlcw==", parsed.tx_bytes.?);
}

test "parseCliArgs supports file-backed tx payload args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    const tx_file = "tmp_cli_tx_bytes.json";
    const opt_file = "tmp_cli_tx_payload_options.json";

    try cwd.writeFile(.{ .sub_path = tx_file, .data = "ZHVtbXlfdHhfYnl0ZXM=" });
    try cwd.writeFile(.{ .sub_path = opt_file, .data = "{\"showInput\":true}" });
    defer cwd.deleteFile(tx_file) catch {};
    defer cwd.deleteFile(opt_file) catch {};

    const tx_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{tx_file});
    defer allocator.free(tx_file_arg);
    const opt_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{opt_file});
    defer allocator.free(opt_file_arg);

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        tx_file_arg,
        "--signature",
        "sig-file",
        "--options",
        opt_file_arg,
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqualStrings("ZHVtbXlfdHhfYnl0ZXM=", parsed.tx_bytes.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-file", parsed.signatures.items[0]);
    try testing.expectEqualStrings("{\"showInput\":true}", parsed.tx_options.?);
    try testing.expect(!parsed.from_keystore);
    try testing.expectEqual(@as(usize, 0), parsed.signers.items.len);
}

test "parseCliArgs supports file-backed gas payment in programmatic tx payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    const gas_file = "tmp_cli_tx_programmatic_gas_payment.json";

    try cwd.writeFile(.{ .sub_path = gas_file, .data = "[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"digest-gas\"}]" });
    defer cwd.deleteFile(gas_file) catch {};

    const gas_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{gas_file});
    defer allocator.free(gas_file_arg);

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        "--gas-payment",
        gas_file_arg,
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqualStrings("[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"digest-gas\"}]", parsed.tx_build_gas_payment.?);
}

test "parseCliArgs parses auto gas payment for programmatic tx payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        "--auto-gas-payment",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expect(parsed.tx_build_auto_gas_payment);
}

test "parseCliArgs parses gas payment min balance for auto gas payment" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        "--auto-gas-payment",
        "--gas-payment-min-balance",
        "123",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expect(parsed.tx_build_auto_gas_payment);
    try testing.expectEqual(@as(u64, 123), parsed.tx_build_gas_payment_min_balance.?);
}

test "parseCliArgs rejects explicit and auto gas payment together" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        "--gas-payment",
        "[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"digest-gas\"}]",
        "--auto-gas-payment",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects gas payment min balance without auto gas payment" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        "--gas-payment-min-balance",
        "123",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs supports signature-file path in tx payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    const tx_file = "tmp_cli_tx_payload_bytes.json";
    const opt_file = "tmp_cli_tx_payload_options.json";
    const sig_file = "tmp_cli_tx_signature.txt";

    try cwd.writeFile(.{ .sub_path = tx_file, .data = "ZHVtbXlfdHhfYnl0ZXM=" });
    try cwd.writeFile(.{ .sub_path = opt_file, .data = "{\"showInput\":true}" });
    try cwd.writeFile(.{ .sub_path = sig_file, .data = "sig-path-file\n" });
    defer cwd.deleteFile(tx_file) catch {};
    defer cwd.deleteFile(opt_file) catch {};
    defer cwd.deleteFile(sig_file) catch {};

    const tx_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{tx_file});
    defer allocator.free(tx_file_arg);
    const opt_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{opt_file});
    defer allocator.free(opt_file_arg);

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        tx_file_arg,
        "--signature-file",
        sig_file,
        "--options",
        opt_file_arg,
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqualStrings("ZHVtbXlfdHhfYnl0ZXM=", parsed.tx_bytes.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-path-file", parsed.signatures.items[0]);
    try testing.expectEqualStrings("{\"showInput\":true}", parsed.tx_options.?);
    try testing.expect(!parsed.from_keystore);
    try testing.expectEqual(@as(usize, 0), parsed.signers.items.len);
}

test "parseCliArgs parses --signer selector for tx_send" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--signer",
        "dev-account",
        "--from-keystore",
        "--signature",
        "sig-a",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expect(parsed.from_keystore);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("dev-account", parsed.signers.items[0]);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
}

test "parseCliArgs accepts tx_send with --signer and no signatures" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--signer",
        "dev-account",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("dev-account", parsed.signers.items[0]);
    try testing.expectEqual(@as(usize, 0), parsed.signatures.items.len);
}

test "parseCliArgs trims whitespace from file-backed signer selector" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const selector_file = "tmp_cli_signer_selector_with_ws";
    var selector = try std.fs.cwd().createFile(selector_file, .{ .truncate = true });
    defer selector.close();
    defer std.fs.cwd().deleteFile(selector_file) catch {};
    try selector.writeAll("  dev-account\n");

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--signer",
        "@" ++ selector_file,
        "--from-keystore",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expect(parsed.from_keystore);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("dev-account", parsed.signers.items[0]);
}

test "parseCliArgs parses --signer selector for tx payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--signer",
        "dev-account",
        "--from-keystore",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expect(parsed.from_keystore);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("dev-account", parsed.signers.items[0]);
}

test "parseCliArgs trims whitespace from file-backed sender" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sender_file = "tmp_cli_sender_with_ws";
    var sender = try std.fs.cwd().createFile(sender_file, .{ .truncate = true });
    defer sender.close();
    defer std.fs.cwd().deleteFile(sender_file) catch {};
    try sender.writeAll("  0xabc\n");

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--sender",
        "@" ++ sender_file,
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
}

test "parseCliArgs supports --from-keystore for tx send" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--from-keystore",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expect(parsed.from_keystore);
}

test "parseCliArgs supports --from-keystore for tx payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--from-keystore",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expect(parsed.from_keystore);
}

test "parseCliArgs parses tx_payload programmable command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        "--sender",
        "0xabc",
        "--gas-budget",
        "1200",
        "--gas-price",
        "7",
        "--signature",
        "sig-a",
        "--options",
        "{\"skipChecks\":true}",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(u64, 1200), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 7), parsed.tx_build_gas_price.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
    try testing.expectEqualStrings("{\"skipChecks\":true}", parsed.tx_options.?);
}

test "parseCliArgs parses tx_payload --commands from file" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands_file = "tmp_cli_tx_payload_commands.json";
    const commands_json = "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}";
    try std.fs.cwd().writeFile(.{ .sub_path = commands_file, .data = commands_json });
    defer std.fs.cwd().deleteFile(commands_file) catch {};

    const commands_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{commands_file});
    defer allocator.free(commands_file_arg);

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        commands_file_arg,
        "--sender",
        "0xabc",
        "--signature",
        "sig-a",
        "--options",
        "{\"skipChecks\":true}",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
    try testing.expectEqualStrings("{\"skipChecks\":true}", parsed.tx_options.?);
}

test "parseCliArgs parses tx_send --command from file" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const command_file = "tmp_cli_tx_send_command.json";
    const command_json = "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}";
    try std.fs.cwd().writeFile(.{ .sub_path = command_file, .data = command_json });
    defer std.fs.cwd().deleteFile(command_file) catch {};

    const command_file_arg = try std.fmt.allocPrint(allocator, "@{s}", .{command_file});
    defer allocator.free(command_file_arg);

    const args = [_][]const u8{
        "tx",
        "send",
        "--command",
        command_file_arg,
        "--signature",
        "sig-a",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
}

test "parseCliArgs parses tx_payload repeatable command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--command",
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}",
        "--command",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expect(parsed.tx_build_commands == null);
    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
}

test "parseCliArgs supports file-backed typed command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const objects_file = "tmp_cli_tx_payload_transfer_objects.json";
    const address_file = "tmp_cli_tx_payload_transfer_address.json";
    defer _ = std.fs.cwd().deleteFile(objects_file) catch {};
    defer _ = std.fs.cwd().deleteFile(address_file) catch {};

    {
        var file = try std.fs.cwd().createFile(objects_file, .{ .truncate = true });
        defer file.close();
        try file.writeAll("[\"0xcoin\"]");
    }
    {
        var file = try std.fs.cwd().createFile(address_file, .{ .truncate = true });
        defer file.close();
        try file.writeAll("\"0xreceiver\"");
    }

    const objects_arg = try std.fmt.allocPrint(allocator, "@{s}", .{objects_file});
    defer allocator.free(objects_arg);
    const address_arg = try std.fmt.allocPrint(allocator, "@{s}", .{address_file});
    defer allocator.free(address_arg);

    const args = [_][]const u8{
        "tx",
        "payload",
        "--transfer-objects",
        objects_arg,
        address_arg,
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);

    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer command.deinit();
    try testing.expectEqualStrings("TransferObjects", command.value.array.items[0].object.get("kind").?.string);
}

test "parseCliArgs supports typed move-call command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--move-call",
        "0x2",
        "counter",
        "increment",
        "[]",
        "[\"0xabc\"]",
        "--transfer-objects",
        "[\"0xcoin\"]",
        "\"0xreceiver\"",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer second.deinit();

    try testing.expectEqualStrings("MoveCall", first.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", second.value.array.items[0].object.get("kind").?.string);
}

test "parseCliArgs resolves package aliases inside typed move-call command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--move-call",
        "cetus_clmm_mainnet",
        "pool",
        "swap",
        "[]",
        "[\"0xabc\"]",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer first.deinit();
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, first.value.array.items[0].object.get("package").?.string);
}

test "parseCliArgs supports structured typed move-call command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--move-call",
        "0x2",
        "counter",
        "increment",
        "--move-call-type-arg",
        "0x2::sui::SUI",
        "--move-call-arg",
        "0xabc",
        "--move-call-arg",
        "7",
        "--transfer-objects",
        "[\"0xcoin\"]",
        "\"0xreceiver\"",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer first.deinit();
    try testing.expectEqualStrings("MoveCall", first.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("0x2::sui::SUI", first.value.array.items[0].object.get("typeArguments").?.array.items[0].string);
    try testing.expectEqualStrings("0xabc", first.value.array.items[0].object.get("arguments").?.array.items[0].string);
    try testing.expectEqual(@as(i64, 7), first.value.array.items[0].object.get("arguments").?.array.items[1].integer);
}

test "parseCliArgs supports structured transfer split and merge command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--transfer-objects",
        "--transfer-object",
        "0xcoin_a",
        "--transfer-object",
        "0xcoin_b",
        "--transfer-address",
        "0xreceiver",
        "--split-coins",
        "--split-coin",
        "0xgas",
        "--split-amount",
        "1",
        "--split-amount",
        "2",
        "--merge-coins",
        "--merge-destination",
        "0xdest",
        "--merge-source",
        "0xsrc_a",
        "--merge-source",
        "0xsrc_b",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), parsed.tx_build_command_items.items.len);

    const transfer = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer transfer.deinit();
    const split = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer split.deinit();
    const merge = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[2], .{});
    defer merge.deinit();

    try testing.expectEqualStrings("TransferObjects", transfer.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("0xcoin_a", transfer.value.array.items[0].object.get("objects").?.array.items[0].string);
    try testing.expectEqualStrings("0xcoin_b", transfer.value.array.items[0].object.get("objects").?.array.items[1].string);
    try testing.expectEqualStrings("0xreceiver", transfer.value.array.items[0].object.get("address").?.string);

    try testing.expectEqualStrings("SplitCoins", split.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("0xgas", split.value.array.items[0].object.get("coin").?.string);
    try testing.expectEqual(@as(i64, 1), split.value.array.items[0].object.get("amounts").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 2), split.value.array.items[0].object.get("amounts").?.array.items[1].integer);

    try testing.expectEqualStrings("MergeCoins", merge.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("0xdest", merge.value.array.items[0].object.get("destination").?.string);
    try testing.expectEqualStrings("0xsrc_a", merge.value.array.items[0].object.get("sources").?.array.items[0].string);
    try testing.expectEqualStrings("0xsrc_b", merge.value.array.items[0].object.get("sources").?.array.items[1].string);
}

test "parseCliArgs parses tx_payload move-call command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--sender",
        "0xabc",
        "--gas-budget",
        "1200",
        "--gas-price",
        "9",
        "--signature",
        "sig-a",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.tx_build_package.?);
    try testing.expectEqualStrings("counter", parsed.tx_build_module.?);
    try testing.expectEqualStrings("increment", parsed.tx_build_function.?);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(u64, 1200), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 9), parsed.tx_build_gas_price.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
}

test "parseCliArgs parses tx_send move-call command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--signature",
        "sig-a",
        "--sender",
        "0xabc",
        "--gas-budget",
        "900",
        "--gas-price",
        "10",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.tx_build_package.?);
    try testing.expectEqualStrings("counter", parsed.tx_build_module.?);
    try testing.expectEqualStrings("increment", parsed.tx_build_function.?);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(u64, 900), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 10), parsed.tx_build_gas_price.?);
    try testing.expectEqual(@as(usize, 1), parsed.signatures.items.len);
    try testing.expectEqualStrings("sig-a", parsed.signatures.items[0]);
}

test "parseCliArgs parses tx_send --wait flag" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--signature",
        "sig-a",
        "--wait",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expect(parsed.tx_send_wait);
}

test "parseCliArgs rejects session response without standalone provider config" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--gas-budget",
        "1200",
        "--signature",
        "sig-a",
        "--session-response",
        "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-1\"}}",
    }));
}

test "parseCliArgs parses tx_send standalone provider continuation" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--gas-budget",
        "1200",
        "--provider",
        "{\"kind\":\"passkey\",\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-1\"},\"challenge\":{\"passkey\":{\"rpId\":\"wallet.example\",\"challengeB64url\":\"challenge-1\"}},\"authorizer\":{\"exec\":[\"wallet-helper\",\"authorize\"]}}",
        "--session-response",
        "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-1-approved\"}}",
    });
    defer parsed.deinit(allocator);

    try testing.expect(parsed.tx_provider_config != null);
    try testing.expectEqualStrings("{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-1-approved\"}}", parsed.tx_session_response.?);
}

test "parseCliArgs parses tx_simulate standalone provider continuation" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "simulate",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--gas-budget",
        "1200",
        "--provider",
        "{\"kind\":\"passkey\",\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-2\"},\"challenge\":{\"passkey\":{\"rpId\":\"wallet.example\",\"challengeB64url\":\"challenge-2\"}},\"authorizer\":{\"exec\":[\"wallet-helper\",\"authorize\"]}}",
        "--session-response",
        "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-2\"}}",
    });
    defer parsed.deinit(allocator);

    try testing.expect(parsed.tx_provider_config != null);
    try testing.expect(parsed.tx_session_response != null);
}

test "parseCliArgs parses tx_build standalone provider continuation" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "build",
        "programmable",
        "--command",
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
        "--emit-tx-block",
        "--provider",
        "{\"kind\":\"passkey\",\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-3\"},\"challenge\":{\"passkey\":{\"rpId\":\"wallet.example\",\"challengeB64url\":\"challenge-3\"}},\"authorizer\":{\"exec\":[\"wallet-helper\",\"authorize\"]}}",
        "--session-response",
        "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-3\"}}",
    });
    defer parsed.deinit(allocator);

    try testing.expect(parsed.tx_provider_config != null);
    try testing.expect(parsed.tx_session_response != null);
}

test "parseCliArgs parses tx_payload standalone provider continuation" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "payload",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--gas-budget",
        "1200",
        "--provider",
        "{\"kind\":\"passkey\",\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-4\"},\"challenge\":{\"passkey\":{\"rpId\":\"wallet.example\",\"challengeB64url\":\"challenge-4\"}},\"authorizer\":{\"exec\":[\"wallet-helper\",\"authorize\"]}}",
        "--session-response",
        "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"session-4\"}}",
    });
    defer parsed.deinit(allocator);

    try testing.expect(parsed.tx_provider_config != null);
    try testing.expect(parsed.tx_session_response != null);
}

test "parseCliArgs rejects zero poll interval" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "--poll-ms",
        "0",
        "tx",
        "confirm",
        "0xdigest",
    }));
}

test "parseCliArgs parses tx_send summarize and observe flags" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summarized = try parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--tx-bytes",
        "AAAA",
        "--signature",
        "sig-a",
        "--summarize",
    });
    defer summarized.deinit(allocator);
    try testing.expect(summarized.tx_send_summarize);
    try testing.expect(!summarized.tx_send_observe);

    var observed = try parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--tx-bytes",
        "AAAA",
        "--signature",
        "sig-a",
        "--observe",
    });
    defer observed.deinit(allocator);
    try testing.expect(!observed.tx_send_summarize);
    try testing.expect(observed.tx_send_observe);
}

test "parseCliArgs rejects tx_send summarize and observe together" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--tx-bytes",
        "AAAA",
        "--signature",
        "sig-a",
        "--summarize",
        "--observe",
    }));
}

test "parseCliArgs parses tx_status summarize and tx_confirm observe flags" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var status_args = try parseCliArgs(allocator, &.{
        "tx",
        "status",
        "0xdigest",
        "--summarize",
    });
    defer status_args.deinit(allocator);
    try testing.expect(status_args.tx_send_summarize);
    try testing.expect(!status_args.tx_send_observe);

    var confirm_args = try parseCliArgs(allocator, &.{
        "tx",
        "confirm",
        "0xdigest",
        "--observe",
    });
    defer confirm_args.deinit(allocator);
    try testing.expect(!confirm_args.tx_send_summarize);
    try testing.expect(confirm_args.tx_send_observe);
}

test "parseCliArgs rejects tx_confirm summarize and observe together" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "tx",
        "confirm",
        "0xdigest",
        "--summarize",
        "--observe",
    }));
}

test "parseCliArgs parses tx_simulate summarize flag" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "simulate",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--sender",
        "0xabc",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_simulate, parsed.command);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses tx_dry_run tx-bytes mode" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "AAAA",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_dry_run, parsed.command);
    try testing.expectEqualStrings("AAAA", parsed.tx_bytes.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses tx_dry_run programmable build context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
        "--function",
        "swap",
        "--gas-budget",
        "1200",
        "--auto-gas-payment",
        "--signer",
        "main",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_dry_run, parsed.command);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.tx_build_package.?);
    try testing.expectEqualStrings("pool", parsed.tx_build_module.?);
    try testing.expectEqualStrings("swap", parsed.tx_build_function.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
    try testing.expect(parsed.tx_build_auto_gas_payment);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
}

test "parseCliArgs parses tx_dry_run request artifact" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200,\"gasPrice\":8,\"gasPayment\":[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"0xdigest\"}],\"summarize\":true}",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_dry_run, parsed.command);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}]",
        parsed.tx_build_commands.?,
    );
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
    try testing.expectEqual(@as(?u64, 8), parsed.tx_build_gas_price);
    try testing.expectEqualStrings(
        "[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"0xdigest\"}]",
        parsed.tx_build_gas_payment.?,
    );
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses tx_dry_run request artifact with auto gas budget" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200,\"gasPrice\":8,\"gasPayment\":[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"0xdigest\"}],\"autoGasBudget\":true,\"summarize\":true}",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_dry_run, parsed.command);
    try testing.expect(parsed.tx_build_auto_gas_budget);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
}

test "parseCliArgs parses tx_dry_run request artifact from stdin" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const old_override = test_stdin_value_override;
    defer test_stdin_value_override = old_override;
    test_stdin_value_override =
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xstdin\",\"gasBudget\":1200,\"gasPrice\":8,\"summarize\":true}";

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--request",
        "@-",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_dry_run, parsed.command);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}]",
        parsed.tx_build_commands.?,
    );
    try testing.expectEqualStrings("0xstdin", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
    try testing.expectEqual(@as(?u64, 8), parsed.tx_build_gas_price);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs rejects tx_dry_run tx-bytes mixed with move-call args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--tx-bytes",
        "AAAA",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
    }));
}

test "parseCliArgs rejects tx_dry_run tx-bytes mixed with signer sources" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--tx-bytes",
        "AAAA",
        "--from-keystore",
    }));
}

test "parseCliArgs parses tx_payload summarize flag" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "payload",
        "--tx-bytes",
        "AAAA",
        "--signature",
        "sig-a",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses tx_build summarize flag" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs rejects tx_send partial move-call options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send move-call options mixed with --commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send move-call options mixed with --command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--command",
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send malformed --command fragment" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--command",
        "\"not-an-object-or-array\"",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send --command object missing kind" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--command",
        "{}",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send commands array containing invalid entry" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[]},\"\"]",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send MoveCall command missing package" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[]}]",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload TransferObjects command missing address" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--command",
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"]}",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send invalid typed transfer command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--transfer-objects",
        "\"0xcoin\"",
        "\"0xreceiver\"",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send tx-bytes mixed with --commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send tx-bytes mixed with gas-budget" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--gas-budget",
        "1200",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send tx-bytes mixed with sender" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--sender",
        "0xabc",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload tx-bytes mixed with gas-price" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--gas-price",
        "9",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload tx-bytes mixed with type-args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--type-args",
        "[]",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload malformed --commands input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--signature",
        "sig-a",
        "--commands",
        "true",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload --commands empty array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--signature",
        "sig-a",
        "--commands",
        "[]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send tx-bytes mixed with move-call args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send with sender context but no tx-bytes/programmatic tx" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--sender",
        "0xabc",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send with partial move-call context fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--type-args",
        "[]",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload with sender context but no tx-bytes/programmatic tx" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--gas-budget",
        "1000",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload tx-bytes mixed with --commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload with partial move-call context fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--args",
        "[\"0xabc\"]",
        "--signature",
        "sig-a",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_simulate positional params with move-call args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "simulate",
        "[{\"some\":\"param\"}]",
        "--args",
        "[\"0xabc\"]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_simulate with sender context but no programmable tx input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "simulate",
        "--sender",
        "0xabc",
        "--params",
        "[{\"some\":\"param\"}]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload tx-bytes mixed with move-call args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_simulate positional params with move-call options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "simulate",
        "[{\"some\":\"param\"}]",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload partial move-call options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--function",
        "increment",
        "--args",
        "[\"0xabc\"]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_payload without tx-bytes/programmatic tx" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send partial move-call options in any field" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--function",
        "increment",
        "--module",
        "counter",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send without tx-bytes/programmatic tx" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx_send with no signatures and no signer source" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs accepts tx_send with --from-keystore as signature source" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--tx-bytes",
        "dGVzdF90eF9ieXRlcw==",
        "--from-keystore",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.signatures.items.len == 0);
}

test "parseCliArgs parses tx_send request artifact from file" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const request_file = "tmp_cli_tx_send_request.json";
    try std.fs.cwd().writeFile(.{
        .sub_path = request_file,
        .data = "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"fromKeystore\":true,\"signer\":\"main\",\"gasBudget\":2200,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}",
    });
    defer std.fs.cwd().deleteFile(request_file) catch {};

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--request",
        "@tmp_cli_tx_send_request.json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}]",
        parsed.tx_build_commands.?,
    );
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.tx_build_auto_gas_payment);
    try testing.expect(parsed.tx_build_auto_gas_budget);
    try testing.expect(parsed.tx_send_wait);
    try testing.expect(parsed.tx_send_summarize);
    try testing.expectEqual(@as(?u64, 2200), parsed.tx_build_gas_budget);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("main", parsed.signers.items[0]);
}

test "parseCliArgs parses tx_send request artifact from stdin" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const old_override = test_stdin_value_override;
    defer test_stdin_value_override = old_override;
    test_stdin_value_override =
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"fromKeystore\":true,\"signer\":\"stdin\",\"gasBudget\":2200,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}";

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--request",
        "@-",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}]",
        parsed.tx_build_commands.?,
    );
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.tx_build_auto_gas_budget);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("stdin", parsed.signers.items[0]);
}

test "parseCliArgs parses tx_send request artifact from absolute file path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const request_file = "tmp_cli_tx_send_request_absolute.json";
    try std.fs.cwd().writeFile(.{
        .sub_path = request_file,
        .data = "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"fromKeystore\":true,\"signer\":\"absolute\",\"gasBudget\":2200,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}",
    });
    defer std.fs.cwd().deleteFile(request_file) catch {};

    const request_path = try std.fs.cwd().realpathAlloc(allocator, request_file);
    defer allocator.free(request_path);

    const request_arg = try std.mem.concat(allocator, u8, &.{ "@", request_path });
    defer allocator.free(request_arg);

    var parsed = try parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--request",
        request_arg,
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_send, parsed.command);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}]",
        parsed.tx_build_commands.?,
    );
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.tx_build_auto_gas_payment);
    try testing.expect(parsed.tx_build_auto_gas_budget);
    try testing.expect(parsed.tx_send_wait);
    try testing.expect(parsed.tx_send_summarize);
    try testing.expectEqual(@as(?u64, 2200), parsed.tx_build_gas_budget);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("absolute", parsed.signers.items[0]);
}

test "trimOwnedLoadedValue keeps a stable trimmed copy" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const loaded = try allocator.dupe(u8, " \ntrimmed value\t");
    const trimmed = try trimOwnedLoadedValue(allocator, loaded);
    defer allocator.free(trimmed);

    try testing.expectEqualStrings("trimmed value", trimmed);
}

test "parseCliArgs rejects tx_send request artifact mixed with tx-bytes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--request",
        "{\"commands\":[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}],\"fromKeystore\":true}",
        "--tx-bytes",
        "AAAA",
    }));
}

test "parseCliArgs returns error for unknown command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "unsupported",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs parses account list command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "list",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_list, parsed.command);
}

test "parseCliArgs parses account list command with json output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "list",
        "--json",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_list, parsed.command);
    try testing.expect(parsed.account_list_json);
}

test "parseCliArgs parses account info command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "info",
        "main",
        "--json",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_info, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expect(parsed.account_info_json);
}

test "parseCliArgs parses wallet address command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "address",
        "main",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_address, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
}

test "parseCliArgs parses wallet balance command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "balance",
        "main",
        "--coin-type",
        "0x2::sui::SUI",
        "--limit",
        "25",
        "--all",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_balance, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expectEqualStrings("0x2::sui::SUI", parsed.account_coin_type.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_resources_limit);
    try testing.expect(parsed.account_resources_all);
}

test "parseCliArgs parses wallet coins command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "coins",
        "main",
        "--coin-type",
        "0x2::sui::SUI",
        "--cursor",
        "cursor-1",
        "--limit",
        "25",
        "--json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_coins, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expectEqualStrings("0x2::sui::SUI", parsed.account_coin_type.?);
    try testing.expectEqualStrings("cursor-1", parsed.account_coins_cursor.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_coins_limit);
    try testing.expect(parsed.account_coins_json);
}

test "parseCliArgs parses wallet objects command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "objects",
        "main",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
        "--limit",
        "10",
        "--json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_objects, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.account_objects_package.?);
    try testing.expectEqualStrings("pool", parsed.account_objects_module.?);
    try testing.expectEqual(@as(?u64, 10), parsed.account_objects_limit);
    try testing.expect(parsed.account_objects_json);
}

test "parseCliArgs parses wallet create command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "create",
        "--alias",
        "main",
        "--json",
        "--no-activate",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_create, parsed.command);
    try testing.expectEqualStrings("main", parsed.wallet_alias.?);
    try testing.expect(parsed.wallet_json);
    try testing.expect(!parsed.wallet_activate);
}

test "parseCliArgs parses wallet import command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "import",
        "raw-private-key",
        "--alias",
        "imported",
        "--json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_import, parsed.command);
    try testing.expectEqualStrings("raw-private-key", parsed.wallet_private_key.?);
    try testing.expectEqualStrings("imported", parsed.wallet_alias.?);
    try testing.expect(parsed.wallet_json);
    try testing.expect(parsed.wallet_activate);
}

test "parseCliArgs parses wallet use command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "use",
        "main",
        "--json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_use, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expect(parsed.wallet_json);
}

test "parseCliArgs parses wallet export-public command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "export-public",
        "main",
        "--json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_export_public, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expect(parsed.wallet_json);
}

test "parseCliArgs parses wallet signer inspect command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "signer",
        "inspect",
        "main",
        "--json",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_signer_inspect, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expect(parsed.wallet_json);
}

test "parseCliArgs parses wallet intent build command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "intent",
        "build",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200}",
        "--network",
        "sui:testnet",
        "--execution-mode",
        "send",
        "--policy",
        "{\"session_key\":\"0x1\"}",
        "--correlation-id",
        "req-1",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_intent_build, parsed.command);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqualStrings("sui:testnet", parsed.intent_network.?);
    try testing.expectEqualStrings("send", parsed.intent_execution_mode.?);
    try testing.expectEqualStrings("{\"session_key\":\"0x1\"}", parsed.intent_policy_json.?);
    try testing.expectEqualStrings("req-1", parsed.request_correlation_id.?);
}

test "parseCliArgs parses wallet intent dry-run command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "intent",
        "dry-run",
        "--intent",
        "{\"artifact_kind\":\"wallet_intent\",\"network\":\"sui:mainnet\",\"execution_mode\":\"dry_run\",\"request\":{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0x123\",\"gasBudget\":1200}}",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_intent_dry_run, parsed.command);
    try testing.expectEqualStrings("0x123", parsed.tx_build_sender.?);
    try testing.expectEqualStrings("sui:mainnet", parsed.intent_network.?);
    try testing.expectEqualStrings("dry_run", parsed.intent_execution_mode.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses wallet intent send command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "wallet",
        "intent",
        "send",
        "--intent",
        "{\"artifact_kind\":\"wallet_intent\",\"network\":\"sui:mainnet\",\"request\":{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"fromKeystore\":true,\"signer\":\"0\",\"gasBudget\":1200}}",
        "--observe",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.wallet_intent_send, parsed.command);
    try testing.expectEqualStrings("sui:mainnet", parsed.intent_network.?);
    try testing.expect(parsed.from_keystore);
    try testing.expectEqualStrings("0", parsed.signers.items[0]);
    try testing.expect(parsed.tx_send_observe);
}

test "parseCliArgs parses request build move-call input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "build",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--args",
        "[7]",
        "--sender",
        "0xabc",
        "--gas-budget",
        "1200",
        "--auto-gas-payment",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_build, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.tx_build_package.?);
    try testing.expectEqualStrings("counter", parsed.tx_build_module.?);
    try testing.expectEqualStrings("increment", parsed.tx_build_function.?);
    try testing.expectEqualStrings("[7]", parsed.tx_build_args.?);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
    try testing.expect(parsed.tx_build_auto_gas_payment);
}

test "parseCliArgs parses request inspect artifact" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "inspect",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200}",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_inspect, parsed.command);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}]",
        parsed.tx_build_commands.?,
    );
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
}

test "parseCliArgs parses request dry-run request artifact" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "dry-run",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200,\"summarize\":true}",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_dry_run, parsed.command);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses request send request artifact" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "send",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200}",
        "--from-keystore",
        "--wait",
        "--observe",
        "--provider",
        "{\"kind\":\"remote_signer\"}",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_send, parsed.command);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(?u64, 1200), parsed.tx_build_gas_budget);
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.tx_send_wait);
    try testing.expect(parsed.tx_send_observe);
    try testing.expectEqualStrings("{\"kind\":\"remote_signer\"}", parsed.tx_provider_config.?);
}

test "parseCliArgs parses request sponsor command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "sponsor",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200}",
        "--sponsor-mode",
        "required",
        "--sponsor-policy",
        "{\"tier\":\"vip\"}",
        "--valid-after-ms",
        "100",
        "--valid-before-ms",
        "200",
        "--correlation-id",
        "req-123",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_sponsor, parsed.command);
    try testing.expectEqualStrings("required", parsed.request_sponsor_mode.?);
    try testing.expectEqualStrings("{\"tier\":\"vip\"}", parsed.request_sponsor_policy.?);
    try testing.expectEqual(@as(?u64, 100), parsed.request_valid_after_ms);
    try testing.expectEqual(@as(?u64, 200), parsed.request_valid_before_ms);
    try testing.expectEqualStrings("req-123", parsed.request_correlation_id.?);
}

test "parseCliArgs parses request sign command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "sign",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200}",
        "--provider",
        "{\"kind\":\"remote_signer\"}",
        "--session-response",
        "{\"supportsExecute\":true}",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_sign, parsed.command);
    try testing.expectEqualStrings("{\"kind\":\"remote_signer\"}", parsed.tx_provider_config.?);
    try testing.expectEqualStrings("{\"supportsExecute\":true}", parsed.tx_session_response.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses request schedule command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "schedule",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0xabc\",\"gasBudget\":1200}",
        "--schedule-id",
        "job-1",
        "--replace-schedule-id",
        "job-0",
        "--schedule-at-ms",
        "500",
        "--sponsor-mode",
        "optional",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_schedule, parsed.command);
    try testing.expectEqualStrings("job-1", parsed.request_schedule_id.?);
    try testing.expectEqualStrings("job-0", parsed.request_schedule_replace_id.?);
    try testing.expectEqual(@as(?u64, 500), parsed.request_schedule_at_ms);
    try testing.expectEqualStrings("optional", parsed.request_sponsor_mode.?);
}

test "parseCliArgs parses request list command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "list",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_list, parsed.command);
}

test "parseCliArgs parses request cancel command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "cancel",
        "job-1",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_cancel, parsed.command);
    try testing.expectEqualStrings("job-1", parsed.request_entry_id.?);
}

test "parseCliArgs parses request resume command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "resume",
        "job-1",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_resume, parsed.command);
    try testing.expectEqualStrings("job-1", parsed.request_entry_id.?);
}

test "parseCliArgs parses request rebroadcast command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "rebroadcast",
        "job-1",
        "--from-keystore",
        "--wait",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_rebroadcast, parsed.command);
    try testing.expectEqualStrings("job-1", parsed.request_entry_id.?);
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.tx_send_wait);
}

test "parseCliArgs parses request status command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "request",
        "status",
        "0xdigest",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.request_status, parsed.command);
    try testing.expectEqualStrings("0xdigest", parsed.tx_digest.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses account coins command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "coins",
        "main",
        "--coin-type",
        "0x2::sui::SUI",
        "--limit",
        "25",
        "--all",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_coins, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expectEqualStrings("0x2::sui::SUI", parsed.account_coin_type.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_coins_limit);
    try testing.expect(parsed.account_coins_all);
}

test "parseCliArgs rejects account coins all mixed with cursor" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "account",
        "coins",
        "main",
        "--all",
        "--cursor",
        "cursor-1",
    }));
}

test "parseCliArgs parses account objects command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "objects",
        "main",
        "--struct-type",
        "0x2::coin::Coin<0x2::sui::SUI>",
        "--show-type",
        "--show-owner",
        "--limit",
        "25",
        "--all",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_objects, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expectEqualStrings("0x2::coin::Coin<0x2::sui::SUI>", parsed.account_objects_struct_type.?);
    try testing.expect(parsed.object_show_type);
    try testing.expect(parsed.object_show_owner);
    try testing.expectEqual(@as(?u64, 25), parsed.account_objects_limit);
    try testing.expect(parsed.account_objects_all);
}

test "parseCliArgs rejects account objects all mixed with cursor" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--all",
        "--cursor",
        "cursor-1",
    }));
}

test "parseCliArgs rejects account objects raw and typed filters together" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--filter",
        "{\"StructType\":\"0x2::coin::Coin<0x2::sui::SUI>\"}",
        "--struct-type",
        "0x2::coin::Coin<0x2::sui::SUI>",
    }));
}

test "parseCliArgs parses account objects package and module filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--package",
        "0x2",
        "--module",
        "coin",
        "--limit",
        "25",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_objects, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.account_objects_package.?);
    try testing.expectEqualStrings("coin", parsed.account_objects_module.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_objects_limit);
}

test "parseCliArgs resolves account objects package aliases" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_objects, parsed.command);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.account_objects_package.?);
    try testing.expectEqualStrings("pool", parsed.account_objects_module.?);
}

test "parseCliArgs parses account objects object-id filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--object-id",
        "0xobject-1",
        "--limit",
        "25",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_objects, parsed.command);
    try testing.expectEqualStrings("0xobject-1", parsed.account_objects_object_id.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_objects_limit);
}

test "parseCliArgs rejects account objects module without package" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--module",
        "coin",
    }));
}

test "parseCliArgs rejects account objects object-id mixed with package filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "account",
        "objects",
        "main",
        "--object-id",
        "0xobject-1",
        "--package",
        "0x2",
    }));
}

test "parseCliArgs parses account resources command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "resources",
        "main",
        "--coin-type",
        "0x2::sui::SUI",
        "--struct-type",
        "0x2::coin::Coin<0x2::sui::SUI>",
        "--show-type",
        "--limit",
        "25",
        "--all",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_resources, parsed.command);
    try testing.expectEqualStrings("main", parsed.account_selector.?);
    try testing.expectEqualStrings("0x2::sui::SUI", parsed.account_coin_type.?);
    try testing.expectEqualStrings("0x2::coin::Coin<0x2::sui::SUI>", parsed.account_objects_struct_type.?);
    try testing.expect(parsed.object_show_type);
    try testing.expectEqual(@as(?u64, 25), parsed.account_resources_limit);
    try testing.expect(parsed.account_resources_all);
}

test "parseCliArgs rejects account resources raw and typed filters together" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "account",
        "resources",
        "main",
        "--filter",
        "{\"StructType\":\"0x2::coin::Coin<0x2::sui::SUI>\"}",
        "--struct-type",
        "0x2::coin::Coin<0x2::sui::SUI>",
    }));
}

test "parseCliArgs parses account resources package and module filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "account",
        "resources",
        "main",
        "--package",
        "0x2",
        "--module",
        "coin",
        "--limit",
        "25",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_resources, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.account_objects_package.?);
    try testing.expectEqualStrings("coin", parsed.account_objects_module.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_resources_limit);
}

test "parseCliArgs resolves account resources package aliases" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "account",
        "resources",
        "main",
        "--package",
        "preset:cetus.mainnet.clmm",
        "--module",
        "pool",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_resources, parsed.command);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.account_objects_package.?);
    try testing.expectEqualStrings("pool", parsed.account_objects_module.?);
}

test "parseCliArgs parses account resources object-id filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "account",
        "resources",
        "main",
        "--object-id",
        "0xobject-1",
        "--limit",
        "25",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.account_resources, parsed.command);
    try testing.expectEqualStrings("0xobject-1", parsed.account_objects_object_id.?);
    try testing.expectEqual(@as(?u64, 25), parsed.account_resources_limit);
}

test "parseCliArgs parses events move-module command with package alias" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "events",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
        "--limit",
        "5",
        "--descending",
        "--all",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.events, parsed.command);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.event_package.?);
    try testing.expectEqualStrings("pool", parsed.event_module.?);
    try testing.expectEqual(@as(?u64, 5), parsed.event_limit);
    try testing.expect(parsed.event_descending);
    try testing.expect(parsed.event_all);
}

test "parseCliArgs rejects events package filter without module" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "events",
        "--package",
        "cetus_clmm_mainnet",
    }));
}

test "parseCliArgs rejects events raw and typed filters together" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "events",
        "--filter",
        "{\"MoveEventType\":\"0x2::coin::Thing\"}",
        "--event-type",
        "0x2::coin::Thing",
    }));
}

test "parseCliArgs parses move package summarize command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "package",
        "cetus_clmm_mainnet",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_package, parsed.command);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.move_package.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move module command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "module",
        "0x2",
        "coin",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_module, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.move_package.?);
    try testing.expectEqualStrings("coin", parsed.move_module.?);
}

test "parseCliArgs parses move function command with package alias" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "cetus.mainnet.clmm",
        "pool",
        "swap",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.move_package.?);
    try testing.expectEqualStrings("pool", parsed.move_module.?);
    try testing.expectEqualStrings("swap", parsed.move_function.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move function sender and signer context flags" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--sender",
        "0xabc",
        "--signer",
        "builder",
        "--from-keystore",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("builder", parsed.signers.items[0]);
    try testing.expect(parsed.from_keystore);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move function command with type arguments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.move_package.?);
    try testing.expectEqualStrings("pool", parsed.move_module.?);
    try testing.expectEqualStrings("swap", parsed.move_function.?);
    try testing.expectEqualStrings("[\"0x2::sui::SUI\",\"0x2::sui::SUI\"]", parsed.tx_build_type_args.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move function command with explicit args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--arg",
        "7",
        "--arg",
        "true",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings("[7,true]", parsed.tx_build_args.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move function command with indexed explicit args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--arg-at",
        "0",
        "select:{\"kind\":\"object_preset\",\"name\":\"clock\"}",
        "--arg-at",
        "2",
        "7",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings(
        "[{\"index\":0,\"value\":\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"clock\\\"}\"},{\"index\":2,\"value\":7}]",
        parsed.move_function_indexed_args_json.?,
    );
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs rejects move function duplicate indexed explicit args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--arg-at",
        "0",
        "1",
        "--arg-at",
        "0",
        "2",
    }));
}

test "parseCliArgs parses move function command with indexed object args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--object-arg-at",
        "0",
        "clock",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings(
        "[{\"index\":0,\"value\":\"0x6\"}]",
        parsed.move_function_indexed_object_args_json.?,
    );
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move function command with indexed vector object args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "router",
        "deposit_many",
        "--object-arg-at",
        "0",
        "[\"clock\",\"0x1\"]",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqualStrings(
        "[{\"index\":0,\"value\":[\"0x6\",\"0x1\"]}]",
        parsed.move_function_indexed_object_args_json.?,
    );
}

test "parseCliArgs rejects move function duplicate indexed object args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--object-arg-at",
        "0",
        "0x1",
        "--object-arg-at",
        "0",
        "0x2",
    }));
}

test "parseCliArgs parses move function command with emitted template output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--emit-template",
        "preferred-dry-run-request",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expectEqual(MoveFunctionTemplateOutput.preferred_tx_dry_run_request, parsed.move_function_template_output.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses move function direct execution flags" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--send",
        "--wait",
        "--signer",
        "builder",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.move_function, parsed.command);
    try testing.expect(parsed.move_function_execute_send);
    try testing.expect(!parsed.move_function_execute_dry_run);
    try testing.expect(parsed.tx_send_wait);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("builder", parsed.signers.items[0]);
}

test "parseCliArgs parses move function standalone provider continuation" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--send",
        "--provider",
        "{\"kind\":\"passkey\",\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"session\":{\"kind\":\"passkey\",\"sessionId\":\"move-function-session\"},\"challenge\":{\"passkey\":{\"rpId\":\"wallet.example\",\"challengeB64url\":\"challenge-move-function\"}},\"authorizer\":{\"exec\":[\"wallet-helper\",\"authorize\"]}}",
        "--session-response",
        "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"move-function-approved\"}}",
    });
    defer parsed.deinit(allocator);

    try testing.expect(parsed.move_function_execute_send);
    try testing.expect(parsed.tx_provider_config != null);
    try testing.expect(parsed.tx_session_response != null);
}

test "parseCliArgs rejects move function direct execution mixed with emitted template output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--dry-run",
        "--emit-template",
        "preferred-dry-run-request",
    }));
}

test "parseCliArgs rejects move function wait without direct send" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--wait",
    }));
}

test "parseCliArgs rejects move function provider without direct execution" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--provider",
        "{\"kind\":\"passkey\",\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"authorizer\":{\"exec\":[\"wallet-helper\",\"authorize\"]}}",
    }));
}

test "parseCliArgs parses object get summarize options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "get",
        "0xobject",
        "--options",
        "{\"showType\":true}",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_get, parsed.command);
    try testing.expectEqualStrings("0xobject", parsed.object_id.?);
    try testing.expectEqualStrings("{\"showType\":true}", parsed.object_options.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses object get typed option flags" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "get",
        "0xobject",
        "--show-type",
        "--show-owner",
        "--show-storage-rebate",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_get, parsed.command);
    try testing.expectEqualStrings("0xobject", parsed.object_id.?);
    try testing.expect(parsed.object_show_type);
    try testing.expect(parsed.object_show_owner);
    try testing.expect(parsed.object_show_storage_rebate);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs resolves object preset aliases for object get" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "get",
        "clock",
        "--show-type",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_get, parsed.command);
    try testing.expectEqualStrings(object_preset.clock, parsed.object_id.?);
    try testing.expect(parsed.object_show_type);
}

test "parseCliArgs rejects object get raw options mixed with typed flags" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "object",
        "get",
        "0xobject",
        "--options",
        "{\"showType\":true}",
        "--show-owner",
    }));
}

test "parseCliArgs parses object dynamic-fields options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "dynamic-fields",
        "0xparent",
        "--limit",
        "25",
        "--all",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_dynamic_fields, parsed.command);
    try testing.expectEqualStrings("0xparent", parsed.object_parent_id.?);
    try testing.expectEqual(@as(?u64, 25), parsed.object_dynamic_fields_limit);
    try testing.expect(parsed.object_dynamic_fields_all);
}

test "parseCliArgs resolves object preset aliases for object dynamic-fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "dynamic-fields",
        "preset:cetus.mainnet.clmm.global_config",
        "--limit",
        "1",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_dynamic_fields, parsed.command);
    try testing.expectEqualStrings(
        object_preset.cetus_clmm_global_config_mainnet,
        parsed.object_parent_id.?,
    );
    try testing.expectEqual(@as(?u64, 1), parsed.object_dynamic_fields_limit);
}

test "parseCliArgs parses object dynamic-field-object summarize" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "dynamic-field-object",
        "0xparent",
        "{\"type\":\"address\",\"value\":\"0xowner\"}",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_dynamic_field_object, parsed.command);
    try testing.expectEqualStrings("0xparent", parsed.object_parent_id.?);
    try testing.expectEqualStrings("{\"type\":\"address\",\"value\":\"0xowner\"}", parsed.object_dynamic_field_name.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs parses object dynamic-field-object typed name inputs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "dynamic-field-object",
        "0xparent",
        "--name-type",
        "address",
        "--name-value",
        "\"0xowner\"",
        "--summarize",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_dynamic_field_object, parsed.command);
    try testing.expectEqualStrings("0xparent", parsed.object_parent_id.?);
    try testing.expectEqualStrings("address", parsed.object_dynamic_field_name_type.?);
    try testing.expectEqualStrings("\"0xowner\"", parsed.object_dynamic_field_name_value.?);
    try testing.expect(parsed.tx_send_summarize);
}

test "parseCliArgs resolves object preset aliases for object dynamic-field-object" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed = try parseCliArgs(allocator, &.{
        "object",
        "dynamic-field-object",
        "cetus_clmm_global_config_mainnet",
        "--name-type",
        "address",
        "--name-value",
        "\"0xowner\"",
    });
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.object_dynamic_field_object, parsed.command);
    try testing.expectEqualStrings(
        object_preset.cetus_clmm_global_config_mainnet,
        parsed.object_parent_id.?,
    );
    try testing.expectEqualStrings("address", parsed.object_dynamic_field_name_type.?);
    try testing.expectEqualStrings("\"0xowner\"", parsed.object_dynamic_field_name_value.?);
}

test "parseCliArgs rejects object dynamic-field-object mixed raw and typed names" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "object",
        "dynamic-field-object",
        "0xparent",
        "{\"type\":\"address\",\"value\":\"0xowner\"}",
        "--name-type",
        "address",
        "--name-value",
        "\"0xowner\"",
    }));
}

test "parseCliArgs rejects object dynamic-fields all mixed with cursor" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "object",
        "dynamic-fields",
        "0xparent",
        "--cursor",
        "cursor-1",
        "--all",
    }));
}

test "parseCliArgs returns error for unknown object subcommand" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &.{
        "object",
        "unknown",
    }));
}

test "parseCliArgs parses tx build move-call transaction block options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--sender",
        "0xabc",
        "--gas-budget",
        "999",
        "--gas-price",
        "11",
        "--emit-tx-block",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expect(parsed.tx_build_emit_tx_block);
    try testing.expectEqual(@as(u64, 999), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 11), parsed.tx_build_gas_price.?);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
}

test "parseCliArgs parses tx build programmable command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x1\",\"module\":\"mod\",\"function\":\"f\",\"typeArguments\":[],\"arguments\":[]}]",
        "--sender",
        "0xabc",
        "--gas-budget",
        "1000",
        "--gas-price",
        "9",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.programmable, parsed.tx_build_kind.?);
    try testing.expect(parsed.tx_build_emit_tx_block);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(u64, 1000), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 9), parsed.tx_build_gas_price.?);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
}

test "parseCliArgs accepts tx build programmable with unknown future command kind" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--commands",
        "[{\"kind\":\"CustomFutureCommand\",\"value\":1}]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.programmable, parsed.tx_build_kind.?);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("{\"kind\":\"CustomFutureCommand\",\"value\":1}", parsed.tx_build_command_items.items[0]);
}

test "parseCliArgs parses tx build programmable repeatable command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--command",
        "{\"kind\":\"MoveCall\",\"package\":\"0x1\",\"module\":\"mod\",\"function\":\"f\",\"typeArguments\":[],\"arguments\":[]}",
        "--command",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        "--signer",
        "builder",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.programmable, parsed.tx_build_kind.?);
    try testing.expect(parsed.tx_build_emit_tx_block);
    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);
    try testing.expect(parsed.tx_build_commands == null);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("builder", parsed.signers.items[0]);
}

test "parseCliArgs parses tx build programmable typed command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--transfer-objects",
        "[\"0xcoin\"]",
        "\"0xreceiver\"",
        "--split-coins",
        "\"0xcoin\"",
        "[1,2]",
        "--merge-coins",
        "\"0xdest\"",
        "[\"0xsrc\"]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.programmable, parsed.tx_build_kind.?);
    try testing.expectEqual(@as(usize, 3), parsed.tx_build_command_items.items.len);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer second.deinit();
    const third = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[2], .{});
    defer third.deinit();

    try testing.expectEqualStrings("TransferObjects", first.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", second.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("MergeCoins", third.value.array.items[0].object.get("kind").?.string);
}

test "parseCliArgs parses tx build programmable typed move-call fragment" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--move-call",
        "0x2",
        "counter",
        "increment",
        "[]",
        "[\"0xabc\"]",
        "--signer",
        "builder",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.programmable, parsed.tx_build_kind.?);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("builder", parsed.signers.items[0]);

    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer command.deinit();
    try testing.expectEqualStrings("MoveCall", command.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("counter", command.value.array.items[0].object.get("module").?.string);
}

test "parseCliArgs normalizes typed tokens inside immediate programmable move-call args json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--split-coins",
        "gas",
        "[7]",
        "--assign",
        "coin_split",
        "--move-call",
        "0x2",
        "counter",
        "set_values",
        "[]",
        "[\"ptb:name:coin_split:0\",{\"owner\":\"addr:0xdef456\"}]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer command.deinit();
    const args_json = command.value.array.items[0].object.get("arguments").?.array.items;
    try testing.expect(args_json[0] == .object);
    try testing.expectEqual(@as(i64, 0), args_json[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqualStrings("0xdef456", args_json[1].object.get("owner").?.string);
}

test "parseCliArgs parses tx build programmable immediate publish command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--publish",
        "[\"AQID\"]",
        "[\"0x2\"]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.programmable, parsed.tx_build_kind.?);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);

    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer command.deinit();
    try testing.expectEqualStrings("Publish", command.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("AQID", command.value.array.items[0].object.get("modules").?.array.items[0].string);
}

test "parseCliArgs preserves selected request tokens in programmable move-call fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--move-call",
        "0x2",
        "counter",
        "set_selected",
        "--move-call-arg",
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::example::Thing\"}",
        "--move-call-arg",
        "u64:7",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer command.deinit();
    const arguments = command.value.array.items[0].object.get("arguments").?.array;
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::example::Thing\"}",
        arguments.items[0].string,
    );
    try testing.expectEqualStrings("u64:7", arguments.items[1].string);
}

test "parseCliArgs preserves selected request tokens in programmable immediate move-call args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--move-call",
        "0x2",
        "counter",
        "set_selected",
        "[]",
        "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",{\"owner\":\"addr:0xabc\"}]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer command.deinit();
    const arguments = command.value.array.items[0].object.get("arguments").?.array;
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::example::Thing\"}",
        arguments.items[0].string,
    );
    try testing.expectEqualStrings("{\"owner\":\"addr:0xabc\"}", arguments.items[1].string);
}

test "parseCliArgs parses tx payload structured make-move-vec fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--make-move-vec",
        "--make-move-vec-type",
        "0x2::sui::SUI",
        "--make-move-vec-element",
        "ptb:input:0",
        "--make-move-vec-element",
        "0xcoin2",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);

    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer command.deinit();
    try testing.expectEqualStrings("MakeMoveVec", command.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("0x2::sui::SUI", command.value.array.items[0].object.get("type").?.string);
    try testing.expectEqual(@as(usize, 2), command.value.array.items[0].object.get("elements").?.array.items.len);
    try testing.expectEqual(@as(i64, 0), command.value.array.items[0].object.get("elements").?.array.items[0].object.get("Input").?.integer);
}

test "parseCliArgs parses programmable command aliases with --assign and ptb:name" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "--split-coin",
        "ptb:gas",
        "--split-amount",
        "7",
        "--assign",
        "new_coin",
        "--transfer-objects",
        "--transfer-object",
        "ptb:name:new_coin:0",
        "--transfer-address",
        "0xreceiver",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer second.deinit();

    try testing.expectEqualStrings("SplitCoins", first.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", second.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), second.value.array.items[0].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), second.value.array.items[0].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[1].integer);
}

test "parseCliArgs parses programmable immediate upgrade command with assigned ticket alias" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "\"GasCoin\"",
        "[7]",
        "--assign",
        "ticket",
        "--upgrade",
        "[\"BAUG\"]",
        "[\"0x2\",\"0x3\"]",
        "0x42",
        "ptb:name:ticket",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const upgrade = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer upgrade.deinit();
    try testing.expectEqualStrings("Upgrade", upgrade.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("0x42", upgrade.value.array.items[0].object.get("package").?.string);
    try testing.expectEqual(@as(i64, 0), upgrade.value.array.items[0].object.get("ticket").?.object.get("Result").?.integer);
}

test "parseCliArgs resolves package aliases inside typed upgrade command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "\"GasCoin\"",
        "[7]",
        "--assign",
        "ticket",
        "--upgrade",
        "[\"BAUG\"]",
        "[\"0x2\",\"0x3\"]",
        "cetus_clmm_mainnet",
        "ptb:name:ticket",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    const upgrade = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer upgrade.deinit();
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, upgrade.value.array.items[0].object.get("package").?.string);
}

test "parseCliArgs parses tx simulate programmable command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "simulate",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        "--sender",
        "0xabc",
        "--gas-budget",
        "500",
        "--gas-price",
        "11",
        "--options",
        "{\"skipChecks\":true}",
        "--signer",
        "alias-or-key",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_simulate, parsed.command);
    try testing.expectEqual(@as(usize, 1), parsed.tx_build_command_items.items.len);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(u64, 500), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 11), parsed.tx_build_gas_price.?);
    try testing.expectEqualStrings("{\"skipChecks\":true}", parsed.tx_options.?);
    try testing.expectEqual(@as(usize, 1), parsed.signers.items.len);
    try testing.expectEqualStrings("alias-or-key", parsed.signers.items[0]);
}

test "parseCliArgs supports assign after raw --commands input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--commands",
        "[{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[7]}]",
        "--assign",
        "coin_split",
        "--transfer-objects",
        "--transfer-object",
        "ptb:name:coin_split:0",
        "--transfer-address",
        "0xreceiver",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[0], .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer second.deinit();

    try testing.expectEqualStrings("SplitCoins", first.value.object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", second.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), second.value.array.items[0].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), second.value.array.items[0].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[1].integer);
}

test "parseCliArgs supports raw --commands references to assigned aliases" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "gas",
        "[7]",
        "--assign",
        "coin_split",
        "--commands",
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"coin_split.0\"],\"address\":\"@0xdef456\"}]",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const second = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer second.deinit();

    try testing.expectEqualStrings("TransferObjects", second.value.object.get("kind").?.string);
    const object_arg = second.value.object.get("objects").?.array.items[0];
    try testing.expect(object_arg == .object);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqualStrings("0xdef456", second.value.object.get("address").?.string);
}

test "parseCliArgs parses bootcamp shorthand tokens inside move-call args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "--split-coin",
        "gas",
        "--split-amount",
        "u64:7",
        "--assign",
        "coin_split",
        "--move-call",
        "0x2",
        "counter",
        "consume",
        "--move-call-arg",
        "coin_split.0",
        "--move-call-arg",
        "vector[@0xabc123, none, some(@0xdef456)]",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const move_call = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer move_call.deinit();

    try testing.expectEqualStrings("MoveCall", move_call.value.array.items[0].object.get("kind").?.string);
    const arguments = move_call.value.array.items[0].object.get("arguments").?.array.items;
    try testing.expect(arguments[0] == .object);
    try testing.expectEqual(@as(i64, 0), arguments[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), arguments[0].object.get("NestedResult").?.array.items[1].integer);
    try testing.expect(arguments[1] == .array);
    try testing.expectEqualStrings("0xabc123", arguments[1].array.items[0].string);
    try testing.expect(arguments[1].array.items[1] == .null);
    try testing.expectEqualStrings("0xdef456", arguments[1].array.items[2].string);
}

test "parseCliArgs parses bootcamp shorthand tokens inside make-move-vec elements" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "--split-coin",
        "gas",
        "--split-amount",
        "u64:7",
        "--assign",
        "coin_split",
        "--make-move-vec",
        "--make-move-vec-type",
        "0x2::sui::SUI",
        "--make-move-vec-element",
        "@0xabc123",
        "--make-move-vec-element",
        "coin_split.0",
        "--make-move-vec-element",
        "vector[@0xdef456, none]",
        "--sender",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_payload, parsed.command);
    try testing.expectEqual(@as(usize, 2), parsed.tx_build_command_items.items.len);

    const command = try std.json.parseFromSlice(std.json.Value, allocator, parsed.tx_build_command_items.items[1], .{});
    defer command.deinit();

    try testing.expectEqualStrings("MakeMoveVec", command.value.array.items[0].object.get("kind").?.string);
    const elements = command.value.array.items[0].object.get("elements").?.array.items;
    try testing.expectEqual(@as(usize, 3), elements.len);
    try testing.expectEqualStrings("0xabc123", elements[0].string);
    try testing.expect(elements[1] == .object);
    try testing.expectEqual(@as(i64, 0), elements[1].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), elements[1].object.get("NestedResult").?.array.items[1].integer);
    try testing.expect(elements[2] == .array);
    try testing.expectEqualStrings("0xdef456", elements[2].array.items[0].string);
    try testing.expect(elements[2].array.items[1] == .null);
}

test "parseCliArgs parses tx simulate move-call command options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "simulate",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[]",
        "--args",
        "[\"0xabc\"]",
        "--sender",
        "0xabc",
        "--gas-budget",
        "500",
        "--gas-price",
        "11",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_simulate, parsed.command);
    try testing.expectEqualStrings("0x2", parsed.tx_build_package.?);
    try testing.expectEqualStrings("counter", parsed.tx_build_module.?);
    try testing.expectEqualStrings("increment", parsed.tx_build_function.?);
    try testing.expectEqualStrings("0xabc", parsed.tx_build_sender.?);
    try testing.expectEqual(@as(u64, 500), parsed.tx_build_gas_budget.?);
    try testing.expectEqual(@as(u64, 11), parsed.tx_build_gas_price.?);
}

test "parseCliArgs resolves package aliases for tx simulate move-call" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "simulate",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
        "--function",
        "swap",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.tx_build_package.?);
}

test "parseCliArgs parses --signer for tx build" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"mod\",\"function\":\"f\",\"typeArguments\":[],\"arguments\":[]}]",
        "--signer",
        "alias-or-key",
        "--signer",
        "0xabc",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), parsed.signers.items.len);
    try testing.expectEqualStrings("alias-or-key", parsed.signers.items[0]);
    try testing.expectEqualStrings("0xabc", parsed.signers.items[1]);
    try testing.expectEqual(Command.tx_build, parsed.command);
}

test "parseCliArgs parses tx build move-call command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[\"T\"]",
        "--args",
        "[\"0xabc\"]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqual(Command.tx_build, parsed.command);
    try testing.expectEqual(TxBuildKind.move_call, parsed.tx_build_kind.?);
    try testing.expectEqualStrings("0x2", parsed.tx_build_package.?);
    try testing.expectEqualStrings("counter", parsed.tx_build_module.?);
    try testing.expectEqualStrings("increment", parsed.tx_build_function.?);
    try testing.expectEqualStrings("[\"T\"]", parsed.tx_build_type_args.?);
    try testing.expectEqualStrings("[\"0xabc\"]", parsed.tx_build_args.?);
}

test "parseCliArgs resolves package preset prefixes for tx build move-call" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "preset:cetus.mainnet.clmm",
        "--module",
        "pool",
        "--function",
        "swap",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, parsed.tx_build_package.?);
}

test "parseCliArgs builds move-call arrays from repeatable type-arg and arg options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::balance::Balance<0x2::sui::SUI>",
        "--arg",
        "0xabc",
        "--arg",
        "7",
        "--arg",
        "true",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings("[\"0x2::sui::SUI\",\"0x2::balance::Balance<0x2::sui::SUI>\"]", parsed.tx_build_type_args.?);
    try testing.expectEqualStrings("[\"0xabc\",7,true]", parsed.tx_build_args.?);
}

test "parseCliArgs rejects move-call array options mixed with repeatable fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "send",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--type-args",
        "[\"T\"]",
        "--type-arg",
        "0x2::sui::SUI",
        "--arg",
        "0xabc",
        "--signature",
        "sig-a",
        "--sender",
        "0xabc",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs parses move-call repeatable args through shared typed value tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "set_owner",
        "--arg",
        "obj:0xabc123",
        "--arg",
        "addr:0xdef456",
        "--arg",
        "u128:18446744073709551616",
        "--arg",
        "{\"flag\":true}",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings("[\"0xabc123\",\"0xdef456\",18446744073709551616,{\"flag\":true}]", parsed.tx_build_args.?);
}

test "parseCliArgs parses move-call container tokens through shared typed value tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "set_values",
        "--arg",
        "vec:[1,true,\"x\"]",
        "--arg",
        "option:some:{\"enabled\":true}",
        "--arg",
        "option:none",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings("[[1,true,\"x\"],{\"enabled\":true},null]", parsed.tx_build_args.?);
}

test "parseCliArgs preserves selected request tokens in move-call repeatable args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "set_selected",
        "--arg",
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::example::Thing\"}",
        "--arg",
        "u64:7",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",\"u64:7\"]",
        parsed.tx_build_args.?,
    );
}

test "parseCliArgs preserves selected request tokens inside move-call args json arrays" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "set_selected",
        "--args",
        "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",{\"owner\":\"addr:0xabc\"}]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",{\"owner\":\"addr:0xabc\"}]",
        parsed.tx_build_args.?,
    );
}

test "parseCliArgs preserves object-input selected request tokens inside move-call args json arrays" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "pool",
        "--function",
        "swap",
        "--args",
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xabc123\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"mutable\\\":true}\",{\"owner\":\"addr:0xabc\"}]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xabc123\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"mutable\\\":true}\",{\"owner\":\"addr:0xabc\"}]",
        parsed.tx_build_args.?,
    );
}

test "parseCliArgs preserves object-input inline metadata tokens inside move-call args json arrays" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "clocked",
        "--function",
        "touch",
        "--args",
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0x6\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":1}\",\"u64:7\"]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0x6\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":1}\",\"u64:7\"]",
        parsed.tx_build_args.?,
    );
}

test "parseCliArgs preserves object preset tokens inside move-call args json arrays" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "clocked",
        "--function",
        "touch",
        "--args",
        "[\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"clock\\\"}\",\"u64:7\"]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"clock\\\"}\",\"u64:7\"]",
        parsed.tx_build_args.?,
    );
}

test "parseCliArgs normalizes typed tokens inside --args JSON arrays" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "set_values",
        "--args",
        "[\"addr:0xabc123\",{\"owner\":\"obj:0xdef456\"},[\"bytes:0x0a0b\"]]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings("[\"0xabc123\",{\"owner\":\"0xdef456\"},[\"0x0a0b\"]]", parsed.tx_build_args.?);
}

test "parseCliArgs parses official-style shorthand argument tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "set_values",
        "--arg",
        "@0xabc123",
        "--arg",
        "some(@0xdef456)",
        "--arg",
        "vector[@0xabc123, none]",
    };
    var parsed = try parseCliArgs(allocator, &args);
    defer parsed.deinit(allocator);

    try testing.expectEqualStrings("[\"0xabc123\",\"0xdef456\",[\"0xabc123\",null]]", parsed.tx_build_args.?);
}

test "printUsage mentions typed argument value tokens" {
    const testing = std.testing;

    var output = std.ArrayList(u8){};
    defer output.deinit(testing.allocator);

    try printUsage(output.writer(testing.allocator));

    try testing.expect(std.mem.indexOf(u8, output.items, "typed arg tokens:") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "@0x...") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "addr:0x...") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "<alias>[.<idx>]") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "ptb:name:<alias>[:idx]") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "vec:[...]") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "vector[...]") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "some(...)") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "option:some:<json>") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"kind\":\"object_preset\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"kind\":\"object_input\"") != null);
}

test "parseCliArgs rejects move-call fragment args without a pending typed move-call" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--move-call-arg",
        "0xabc",
        "--sender",
        "0xabc",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects transfer fragment args without a pending typed command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--transfer-object",
        "0xcoin",
        "--sender",
        "0xabc",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects make-move-vec fragment args without a pending typed command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--make-move-vec-element",
        "0xcoin",
        "--sender",
        "0xabc",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects unknown assigned command aliases" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--transfer-objects",
        "--transfer-object",
        "ptb:name:missing:0",
        "--transfer-address",
        "0xreceiver",
        "--sender",
        "0xabc",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects pending split fragment without required coin" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "payload",
        "--split-coins",
        "--split-amount",
        "1",
        "--sender",
        "0xabc",
    };

    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx build move-call mixed with --commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[]}]",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx build move-call mixed with --command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "move-call",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
        "--command",
        "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[]}",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx build programmable with move-call fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[]}]",
        "--package",
        "0x2",
        "--module",
        "counter",
        "--function",
        "increment",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs rejects tx build programmable without commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--signer",
        "builder",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}

test "parseCliArgs returns error for unknown account subcommand" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = [_][]const u8{
        "account",
        "unsupported",
    };
    try testing.expectError(error.InvalidCli, parseCliArgs(allocator, &args));
}
