const std = @import("std");
const client = @import("sui_client_zig");
const cli = @import("./cli.zig");
const tx_builder = client.tx_builder;
const RpcRequest = @typeInfo(@typeInfo(@typeInfo(client.rpc_client.RequestSender).@"struct".fields[1].type).pointer.child).@"fn".params[2].type.?;

fn sendExecuteAndMaybeWaitForConfirmation(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    payload: []const u8,
    writer: anytype,
) !void {
    if (args.tx_send_observe) {
        const response = try rpc.sendTxExecute(payload);
        defer rpc.allocator.free(response);

        var observation = try rpc.observeConfirmedExecuteResponse(
            allocator,
            response,
            args.confirm_timeout_ms orelse std.math.maxInt(u64),
            args.confirm_poll_ms,
        );
        defer observation.deinit(allocator);

        try printStructuredJson(writer, observation, args.pretty);
        return;
    }

    const response = if (args.tx_send_wait)
        try rpc.executePayloadAndConfirm(
            payload,
            args.confirm_timeout_ms orelse std.math.maxInt(u64),
            args.confirm_poll_ms,
        )
    else
        try rpc.sendTxExecute(payload);
    defer rpc.allocator.free(response);

    if (args.tx_send_summarize) {
        var insights = try rpc.summarizeExecutionResponse(allocator, response);
        defer insights.deinit(allocator);
        try printStructuredJson(writer, insights, args.pretty);
        return;
    }

    try printResponse(allocator, writer, response, args.pretty);
}

fn sendDryRunAndMaybeSummarize(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    tx_bytes: []const u8,
    writer: anytype,
) !void {
    const payload = try tx_builder.buildDryRunPayload(allocator, tx_bytes);
    defer allocator.free(payload);

    const response = try rpc.sendTxDryRun(payload);
    defer rpc.allocator.free(response);

    if (args.tx_send_summarize) {
        var insights = try rpc.summarizeExecutionResponse(allocator, response);
        defer insights.deinit(allocator);
        try printStructuredJson(writer, insights, args.pretty);
        return;
    }

    try printResponse(allocator, writer, response, args.pretty);
}

fn printResponse(allocator: std.mem.Allocator, writer: anytype, response: []const u8, pretty: bool) !void {
    if (!pretty) {
        try writer.print("{s}\n", .{response});
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    try writer.print("{f}\n", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
}

fn printStructuredJson(writer: anytype, value: anytype, pretty: bool) !void {
    if (pretty) {
        try writer.print("{f}\n", .{std.json.fmt(value, .{ .whitespace = .indent_2 })});
        return;
    }

    try writer.print("{f}\n", .{std.json.fmt(value, .{})});
}

fn selectedMoveFunctionTemplateOutput(
    summary: client.move_result.OwnedMoveFunctionSummary,
    output: cli.MoveFunctionTemplateOutput,
) ![]const u8 {
    const template = summary.call_template orelse return error.InvalidCli;
    return switch (output) {
        .commands => template.commands_json,
        .preferred_commands => template.preferred_commands_json orelse template.commands_json,
        .tx_dry_run_request => template.tx_dry_run_request_json,
        .preferred_tx_dry_run_request => template.preferred_tx_dry_run_request_json orelse template.tx_dry_run_request_json,
        .tx_send_from_keystore_request => template.tx_send_from_keystore_request_json,
        .preferred_tx_send_from_keystore_request => template.preferred_tx_send_from_keystore_request_json orelse template.tx_send_from_keystore_request_json,
    };
}

fn printMoveFunctionTemplateOutput(
    writer: anytype,
    result: client.rpc_client.ReadQueryActionResult,
    output: cli.MoveFunctionTemplateOutput,
) !void {
    const text = switch (result) {
        .summarized => |summary| switch (summary) {
            .move => |move| switch (move) {
                .function => |value| try selectedMoveFunctionTemplateOutput(value, output),
                else => return error.InvalidCli,
            },
            else => return error.InvalidCli,
        },
        else => return error.InvalidCli,
    };
    try writer.print("{s}\n", .{text});
}

fn moveFunctionExecutionRequestArtifact(
    allocator: std.mem.Allocator,
    result: client.rpc_client.ReadQueryActionResult,
    command: cli.Command,
) !MoveFunctionExecutionRequestSelection {
    const output_kind = switch (command) {
        .tx_dry_run => cli.MoveFunctionTemplateOutput.preferred_tx_dry_run_request,
        .tx_send => cli.MoveFunctionTemplateOutput.preferred_tx_send_from_keystore_request,
        else => return error.InvalidCli,
    };

    return switch (result) {
        .summarized => |summary| switch (summary) {
            .move => |move| switch (move) {
                .function => |value| blk: {
                    const template = value.call_template orelse return error.InvalidCli;
                    break :blk try switch (output_kind) {
                        .preferred_tx_dry_run_request => selectExecutableMoveFunctionRequestArtifact(
                            allocator,
                            template.preferred_tx_dry_run_request_json,
                            template.tx_dry_run_request_json,
                        ),
                        .preferred_tx_send_from_keystore_request => selectExecutableMoveFunctionRequestArtifact(
                            allocator,
                            template.preferred_tx_send_from_keystore_request_json,
                            template.tx_send_from_keystore_request_json,
                        ),
                        else => error.InvalidCli,
                    };
                },
                else => return error.InvalidCli,
            },
            else => return error.InvalidCli,
        },
        else => return error.InvalidCli,
    };
}

fn stringContainsUnresolvedMoveFunctionPlaceholder(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "<arg") != null or
        std.mem.indexOf(u8, text, "0x<") != null or
        std.mem.eql(u8, text, "<alias-or-address>");
}

fn jsonValueContainsUnresolvedMoveFunctionPlaceholder(value: std.json.Value) bool {
    return switch (value) {
        .string => |text| stringContainsUnresolvedMoveFunctionPlaceholder(text),
        .array => |array| blk: {
            for (array.items) |item| {
                if (jsonValueContainsUnresolvedMoveFunctionPlaceholder(item)) break :blk true;
            }
            break :blk false;
        },
        .object => |object| blk: {
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "preferredResolution")) continue;
                if (jsonValueContainsUnresolvedMoveFunctionPlaceholder(entry.value_ptr.*)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn ensureExecutableMoveFunctionRequestArtifact(
    allocator: std.mem.Allocator,
    request_json: []const u8,
) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, request_json, .{});
    defer parsed.deinit();
    if (jsonValueContainsUnresolvedMoveFunctionPlaceholder(parsed.value)) {
        return error.UnresolvedMoveFunctionExecutionTemplate;
    }
}

fn moveFunctionRequestArtifactIsExecutable(
    allocator: std.mem.Allocator,
    request_json: []const u8,
) !bool {
    ensureExecutableMoveFunctionRequestArtifact(allocator, request_json) catch |err| switch (err) {
        error.UnresolvedMoveFunctionExecutionTemplate => return false,
        else => return err,
    };
    return true;
}

const MoveFunctionExecutionRequestSelection = struct {
    request_json: []const u8,
    used_preferred: bool,
};

fn selectExecutableMoveFunctionRequestArtifact(
    allocator: std.mem.Allocator,
    preferred_request_json: ?[]const u8,
    base_request_json: []const u8,
) !MoveFunctionExecutionRequestSelection {
    if (preferred_request_json) |preferred| {
        if (try moveFunctionRequestArtifactIsExecutable(allocator, preferred)) {
            return .{
                .request_json = preferred,
                .used_preferred = true,
            };
        }
    }

    if (try moveFunctionRequestArtifactIsExecutable(allocator, base_request_json)) {
        return .{
            .request_json = base_request_json,
            .used_preferred = false,
        };
    }

    return error.UnresolvedMoveFunctionExecutionTemplate;
}

fn buildDerivedMoveFunctionExecutionArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    command: cli.Command,
    request_json: []const u8,
) !cli.ParsedArgs {
    var derived = cli.ParsedArgs{
        .command = command,
        .has_command = true,
        .pretty = args.pretty,
        .confirm_timeout_ms = args.confirm_timeout_ms,
        .confirm_poll_ms = args.confirm_poll_ms,
        .tx_send_wait = args.tx_send_wait,
        .tx_send_summarize = args.tx_send_summarize,
        .tx_send_observe = args.tx_send_observe,
    };
    errdefer derived.deinit(allocator);

    try cli.applyProgrammaticRequestArtifact(allocator, &derived, request_json);

    derived.pretty = args.pretty;
    derived.confirm_timeout_ms = args.confirm_timeout_ms;
    derived.confirm_poll_ms = args.confirm_poll_ms;

    switch (command) {
        .tx_dry_run => {
            derived.tx_send_wait = false;
            derived.tx_send_observe = false;
        },
        .tx_send => {
            if (args.tx_send_observe) {
                derived.tx_send_observe = true;
                derived.tx_send_summarize = false;
            }
            if (args.tx_send_wait) derived.tx_send_wait = true;
        },
        else => return error.InvalidCli,
    }

    return derived;
}

const ParsedSessionChallengeResponse = struct {
    arena: std.heap.ArenaAllocator,
    response: client.tx_request_builder.SessionChallengeResponse,

    fn deinit(self: *ParsedSessionChallengeResponse) void {
        self.arena.deinit();
    }
};

fn jsonObjectFieldAny(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) ?std.json.Value {
    inline for (names) |name| {
        if (object.get(name)) |value| return value;
    }
    return null;
}

fn parseOptionalJsonString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]const u8 {
    const value = jsonObjectFieldAny(object, names) orelse return null;
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCli,
    };
}

fn parseOptionalJsonBool(
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

fn parseOptionalJsonU64(
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

fn parseAccountSessionFromJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !client.tx_request_builder.AccountSession {
    if (value != .object) return error.InvalidCli;

    const kind = blk: {
        const kind_value = jsonObjectFieldAny(value.object, &.{"kind"}) orelse break :blk client.tx_request_builder.AccountSessionKind.none;
        break :blk switch (kind_value) {
            .null => client.tx_request_builder.AccountSessionKind.none,
            .string => |text| std.meta.stringToEnum(client.tx_request_builder.AccountSessionKind, text) orelse return error.InvalidCli,
            else => return error.InvalidCli,
        };
    };

    return .{
        .kind = kind,
        .session_id = try parseOptionalJsonString(allocator, value.object, &.{ "session_id", "sessionId" }),
        .user_id = try parseOptionalJsonString(allocator, value.object, &.{ "user_id", "userId" }),
        .expires_at_ms = try parseOptionalJsonU64(value.object, &.{ "expires_at_ms", "expiresAtMs" }),
    };
}

fn parseSessionChallengeResponseFromJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !client.tx_request_builder.SessionChallengeResponse {
    if (value != .object) return error.InvalidCli;

    const session = if (jsonObjectFieldAny(value.object, &.{"session"})) |session_value|
        switch (session_value) {
            .null => null,
            else => try parseAccountSessionFromJsonValue(allocator, session_value),
        }
    else
        null;

    return .{
        .session = session,
        .supports_execute = (try parseOptionalJsonBool(value.object, &.{ "supports_execute", "supportsExecute" })) orelse true,
    };
}

fn parseSessionChallengeResponseArg(
    allocator: std.mem.Allocator,
    raw: []const u8,
) !ParsedSessionChallengeResponse {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), raw, .{});
    const response = try parseSessionChallengeResponseFromJsonValue(arena.allocator(), parsed.value);
    return .{
        .arena = arena,
        .response = response,
    };
}

const OwnedStringItems = struct {
    items: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *OwnedStringItems, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| allocator.free(item);
        self.items.deinit(allocator);
    }
};

fn tokenStartsSelectedRequest(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    return std.mem.startsWith(u8, trimmed, "select:") or std.mem.startsWith(u8, trimmed, "sel:");
}

fn jsonValueContainsSelectedRequest(value: std.json.Value) bool {
    return switch (value) {
        .string => |text| tokenStartsSelectedRequest(text),
        .array => |array| blk: {
            for (array.items) |item| {
                if (jsonValueContainsSelectedRequest(item)) break :blk true;
            }
            break :blk false;
        },
        .object => |object| blk: {
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (jsonValueContainsSelectedRequest(entry.value_ptr.*)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn moveCallArgsContainSelectedRequestTokens(
    allocator: std.mem.Allocator,
    raw_args: ?[]const u8,
) !bool {
    const args_json = raw_args orelse return false;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;
    return jsonValueContainsSelectedRequest(parsed.value);
}

fn hasSelectedMoveCallArgumentRequests(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !bool {
    if (!hasCompleteTxBuildMoveCallArgs(args)) return false;
    if (hasTxBuildProgrammaticCommands(args)) return false;
    return try moveCallArgsContainSelectedRequestTokens(allocator, args.tx_build_args);
}

fn programmaticCommandsContainSelectedRequestTokens(args: *const cli.ParsedArgs) bool {
    if (args.tx_build_commands) |value| {
        if (std.mem.indexOf(u8, value, "select:") != null or std.mem.indexOf(u8, value, "sel:") != null) return true;
    }
    for (args.tx_build_command_items.items) |item| {
        if (std.mem.indexOf(u8, item, "select:") != null or std.mem.indexOf(u8, item, "sel:") != null) return true;
    }
    return false;
}

fn gasPaymentContainsSelectedRequestToken(args: *const cli.ParsedArgs) bool {
    const value = args.tx_build_gas_payment orelse return false;
    return std.mem.indexOf(u8, value, "select:") != null or std.mem.indexOf(u8, value, "sel:") != null;
}

fn buildMoveCallArgumentTokensFromArgs(
    allocator: std.mem.Allocator,
    raw_args: ?[]const u8,
) !OwnedStringItems {
    var items = OwnedStringItems{};
    errdefer items.deinit(allocator);

    const args_json = raw_args orelse return items;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;

    for (parsed.value.array.items) |entry| {
        const token = switch (entry) {
            .string => try allocator.dupe(u8, entry.string),
            else => try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(entry, .{})}),
        };
        try items.items.append(allocator, token);
    }

    return items;
}

fn buildSelectedMoveCallInstructionFromArgs(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) ![]u8 {
    var argument_tokens = try buildMoveCallArgumentTokensFromArgs(allocator, args.tx_build_args);
    defer argument_tokens.deinit(allocator);

    const sender = try resolvedTxBuildSenderFromArgs(allocator, args);
    defer if (sender) |value| allocator.free(value);

    var values = try rpc.resolveArgumentValuesFromTokensWithDefaultOwner(allocator, argument_tokens.items.items, sender);
    defer values.deinit(allocator);

    const arguments_json = try client.tx_request_builder.buildArgumentValueArray(allocator, values.slice());
    defer allocator.free(arguments_json);

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try writeMoveCallInstruction(
        allocator,
        out.writer(allocator),
        args.tx_build_package.?,
        args.tx_build_module.?,
        args.tx_build_function.?,
        args.tx_build_type_args,
        arguments_json,
    );
    return out.toOwnedSlice(allocator);
}

fn commandRequestConfigFromOptions(
    options: client.tx_request_builder.ProgrammaticRequestOptions,
    sender: ?[]const u8,
) client.tx_request_builder.CommandRequestConfig {
    return .{
        .sender = sender,
        .gas_budget = options.gas_budget,
        .gas_price = options.gas_price,
        .gas_payment_json = options.gas_payment_json,
        .signatures = options.signatures,
        .options_json = options.options_json,
        .wait_for_confirmation = options.wait_for_confirmation,
        .confirm_timeout_ms = options.confirm_timeout_ms,
        .confirm_poll_ms = options.confirm_poll_ms,
    };
}

fn runSelectedProgrammaticAction(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?client.tx_request_builder.AccountProvider,
    action: client.rpc_client.ProgrammaticClientAction,
) !client.rpc_client.ProgrammaticClientActionResult {
    const options = programmaticRequestOptionsFromArgs(args, signatures);
    const resolved_sender = try resolvedTxBuildSenderFromArgs(allocator, args);
    defer if (resolved_sender) |value| allocator.free(value);
    const sender = resolved_sender;
    const config = commandRequestConfigFromOptions(options, sender);

    if (args.tx_build_auto_gas_payment) {
        return try rpc.runCommandsWithAutoGasPaymentWithAccountProvider(
            allocator,
            options.source,
            config,
            provider orelse .none,
            args.tx_build_gas_payment_min_balance,
            action,
        );
    }

    return try rpc.runCommandsResolvingSelectedArgumentTokensWithAccountProvider(
        allocator,
        options.source,
        config,
        provider orelse .none,
        action,
    );
}

fn hasKeystoreBackedSignerSource(args: *const cli.ParsedArgs) bool {
    return args.signers.items.len != 0 or args.from_keystore;
}

fn hasRealBuilderSignerSource(args: *const cli.ParsedArgs) bool {
    return args.signatures.items.len != 0 or hasKeystoreBackedSignerSource(args);
}

fn shouldUseUnsafeMoveCallKeystorePath(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !bool {
    _ = allocator;
    if (!hasKeystoreBackedSignerSource(args)) return false;
    if (!hasCompleteTxBuildMoveCallArgs(args) or hasTxBuildProgrammaticCommands(args)) return false;
    if (args.tx_build_gas_budget == null) return false;
    return true;
}

fn shouldUseUnsafeTransactionBuilderPath(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !bool {
    if (!hasRealBuilderSignerSource(args)) return false;
    if (!cli.supportsProgrammableInput(args)) return false;
    if (args.tx_build_gas_budget == null) return false;
    const supports_real_builder = try client.SuiRpcClient.commandSourceSupportsUnsafeTransactionBuilder(
        allocator,
        commandSourceFromArgs(args),
    );
    if (!supports_real_builder) return false;

    if (hasKeystoreBackedSignerSource(args)) return true;
    if (args.tx_build_sender != null) return true;

    return (try hasSelectedMoveCallArgumentRequests(allocator, args)) or
        programmaticCommandsContainSelectedRequestTokens(args) or
        gasPaymentContainsSelectedRequestToken(args);
}

fn shouldUseUnsafeBatchKeystorePath(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !bool {
    if (!hasKeystoreBackedSignerSource(args)) return false;
    if (!hasTxBuildProgrammaticCommands(args)) return false;
    if (hasCompleteTxBuildMoveCallArgs(args)) return false;
    if (args.tx_build_gas_budget == null) return false;
    return try client.SuiRpcClient.commandSourceSupportsUnsafeBatchTransaction(
        allocator,
        commandSourceFromArgs(args),
    );
}

fn resolvedLocalBuilderGasPaymentJson(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    sender: []const u8,
    effective_gas_budget: ?u64,
    excluded_object_ids: []const []u8,
) !?[]u8 {
    return try rpc.ownResolvedGasPaymentJsonWithDefaultOwnerAndExclusions(
        allocator,
        args.tx_build_gas_payment,
        sender,
        if (args.tx_build_auto_gas_payment)
            args.tx_build_gas_payment_min_balance orelse effective_gas_budget orelse args.tx_build_gas_budget orelse 1
        else
            null,
        excluded_object_ids,
    );
}

const provisional_auto_gas_budget: u64 = 100_000_000;
const auto_gas_budget_min_buffer: u64 = 1_000;
const auto_gas_budget_buffer_divisor: u64 = 5;

fn estimatedGasBudgetFromInsights(
    insights: client.tx_result.OwnedExecutionInsights,
) !u64 {
    const computation_cost = insights.gas_summary.computation_cost orelse 0;
    const storage_cost = insights.gas_summary.storage_cost orelse 0;
    const non_refundable_storage_fee = insights.gas_summary.non_refundable_storage_fee orelse 0;

    const gross_cost = try std.math.add(
        u64,
        try std.math.add(u64, computation_cost, storage_cost),
        non_refundable_storage_fee,
    );
    if (gross_cost == 0) return error.InvalidResponse;

    const buffer = @max(auto_gas_budget_min_buffer, gross_cost / auto_gas_budget_buffer_divisor);
    return try std.math.add(u64, gross_cost, buffer);
}

fn resolvedLocalBuilderGasPrice(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) !?u64 {
    _ = allocator;
    return try rpc.resolveEffectiveGasPrice(args.tx_build_gas_price, args.signatures.items.len != 0);
}

fn extractGasObjectIdFromGasPaymentJson(
    allocator: std.mem.Allocator,
    gas_payment_json: []const u8,
) !?[]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, gas_payment_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array or parsed.value.array.items.len == 0) return null;

    const first = parsed.value.array.items[0];
    if (first != .object) return null;
    const object_id = first.object.get("objectId") orelse return null;
    if (object_id != .string or object_id.string.len == 0) return null;
    return try allocator.dupe(u8, object_id.string);
}

fn resolvedUnsafeMoveCallGasObjectId(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    sender: []const u8,
) !?[]u8 {
    if (try rpc.resolveSelectedGasPaymentJsonWithDefaultOwner(
        allocator,
        args.tx_build_gas_payment,
        sender,
    )) |resolved_gas_payment_json| {
        defer allocator.free(resolved_gas_payment_json);
        return try extractGasObjectIdFromGasPaymentJson(allocator, resolved_gas_payment_json);
    }

    if (args.tx_build_auto_gas_payment) {
        const gas_payment_json = try rpc.selectGasPaymentJson(
            allocator,
            sender,
            args.tx_build_gas_payment_min_balance orelse args.tx_build_gas_budget orelse 1,
        ) orelse return error.SelectionNotFound;
        defer allocator.free(gas_payment_json);
        return try extractGasObjectIdFromGasPaymentJson(allocator, gas_payment_json);
    }

    if (args.tx_build_gas_payment) |value| {
        return try extractGasObjectIdFromGasPaymentJson(allocator, value);
    }

    return null;
}

fn resolvedUnsafeMoveCallSender(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) !?[]const u8 {
    if (try @import("./tx_pipeline.zig").resolvedTxBuildSenderFromArgs(allocator, args)) |sender| {
        return @as(?[]const u8, sender);
    }

    _ = rpc;
    return try client.SuiRpcClient.inferSelectedRequestOwnerFromOptions(
        allocator,
        programmaticRequestOptionsFromArgs(args, &.{}),
    );
}

fn defaultSenderFromProgrammaticProvider(
    provider: client.tx_request_builder.AccountProvider,
) ?[]const u8 {
    return switch (provider) {
        .direct_signatures => |account| account.sender,
        .remote_signer => |account| account.address,
        .zklogin => |account| account.address,
        .passkey => |account| account.address,
        .multisig => |account| account.address,
        else => null,
    };
}

fn allowReferenceGasPriceFallbackForLocalProviderPath(
    provider: client.tx_request_builder.AccountProvider,
) bool {
    return switch (provider) {
        .default_keystore,
        .direct_signatures,
        .remote_signer,
        .zklogin,
        .passkey,
        .multisig,
        => true,
        else => false,
    };
}

fn allowReferenceGasPriceFallbackForLocalSignerPath(
    args: *const cli.ParsedArgs,
) bool {
    return hasRealBuilderSignerSource(args);
}

fn resolvedUnsafeMoveCallArgumentsJson(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    sender: []const u8,
) !?[]u8 {
    if (!(try hasSelectedMoveCallArgumentRequests(allocator, args))) return null;

    var argument_tokens = try buildMoveCallArgumentTokensFromArgs(allocator, args.tx_build_args);
    defer argument_tokens.deinit(allocator);

    var values = try rpc.resolveArgumentValuesFromTokensWithDefaultOwner(
        allocator,
        argument_tokens.items.items,
        sender,
    );
    defer values.deinit(allocator);

    return try client.tx_request_builder.buildArgumentValueArray(allocator, values.slice());
}

fn buildUnsafeSignedExecutePayloadFromDefaultKeystoreTxBytes(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    tx_bytes: []const u8,
) ![]u8 {
    var signed = try client.keystore.signTransactionBytesFromDefaultKeystore(
        allocator,
        tx_bytes,
        .{
            .signer_selectors = args.signers.items,
            .from_keystore = args.from_keystore,
            .infer_sender_from_signers = true,
        },
    );
    defer signed.deinit(allocator);

    return try tx_builder.buildExecutePayload(
        allocator,
        tx_bytes,
        signed.items,
        args.tx_options,
    );
}

fn buildUnsafeExecutePayloadFromResolvedTxBytes(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    tx_bytes: []const u8,
) ![]u8 {
    if (args.signatures.items.len != 0) {
        return try tx_builder.buildExecutePayload(
            allocator,
            tx_bytes,
            args.signatures.items,
            args.tx_options,
        );
    }
    return try buildUnsafeSignedExecutePayloadFromDefaultKeystoreTxBytes(allocator, args, tx_bytes);
}

fn buildUnsafeMoveCallExecutePayloadFromDefaultKeystore(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) ![]u8 {
    const sender = try resolvedUnsafeMoveCallSender(allocator, rpc, args) orelse return error.InvalidCli;
    defer allocator.free(sender);

    const resolved_arguments_json = try resolvedUnsafeMoveCallArgumentsJson(allocator, rpc, args, sender);
    defer if (resolved_arguments_json) |value| allocator.free(value);

    const gas_object_id = try resolvedUnsafeMoveCallGasObjectId(allocator, rpc, args, sender);
    defer if (gas_object_id) |value| allocator.free(value);

    const tx_bytes = try rpc.buildMoveCallTxBytes(
        allocator,
        sender,
        args.tx_build_package.?,
        args.tx_build_module.?,
        args.tx_build_function.?,
        args.tx_build_type_args,
        resolved_arguments_json orelse args.tx_build_args,
        gas_object_id,
        args.tx_build_gas_budget orelse return error.InvalidCli,
    );
    defer allocator.free(tx_bytes);

    return try buildUnsafeSignedExecutePayloadFromDefaultKeystoreTxBytes(allocator, args, tx_bytes);
}

const OwnedUnsafeCommandSource = struct {
    source: tx_builder.CommandSource,
    owned_json: ?[]u8 = null,

    fn deinit(self: *OwnedUnsafeCommandSource, allocator: std.mem.Allocator) void {
        if (self.owned_json) |value| allocator.free(value);
    }
};

fn resolvedUnsafeCommandSource(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    sender: []const u8,
) !OwnedUnsafeCommandSource {
    if (hasCompleteTxBuildMoveCallArgs(args) and !hasTxBuildProgrammaticCommands(args)) {
        const resolved_arguments_json = try resolvedUnsafeMoveCallArgumentsJson(allocator, rpc, args, sender);
        if (resolved_arguments_json) |value| {
            return .{
                .source = .{
                    .move_call = .{
                        .package_id = args.tx_build_package.?,
                        .module = args.tx_build_module.?,
                        .function_name = args.tx_build_function.?,
                        .type_args = args.tx_build_type_args,
                        .arguments = value,
                    },
                },
                .owned_json = value,
            };
        }
        return .{ .source = commandSourceFromArgs(args) };
    }

    const maybe_resolved_commands_json = try rpc.resolveSelectedArgumentTokensInCommandSourceWithDefaultOwner(
        allocator,
        commandSourceFromArgs(args),
        sender,
    );
    if (maybe_resolved_commands_json) |value| {
        return .{
            .source = .{ .commands_json = value },
            .owned_json = value,
        };
    }

    return .{ .source = commandSourceFromArgs(args) };
}

fn buildUnsafeCommandSourceExecutePayload(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) ![]u8 {
    const sender = try resolvedUnsafeMoveCallSender(allocator, rpc, args) orelse return error.InvalidCli;
    defer allocator.free(sender);

    const options = programmaticRequestOptionsFromArgs(args, args.signatures.items);
    const config = commandRequestConfigFromOptions(options, sender);

    if (args.signatures.items.len != 0) {
        if (args.tx_build_auto_gas_payment) {
            return try rpc.buildCommandSourceExecutePayloadWithAutoGasPaymentWithSignatures(
                allocator,
                options.source,
                config,
                args.tx_build_gas_payment_min_balance,
            );
        }
        return try rpc.buildCommandSourceExecutePayloadResolvingSelectedArgumentTokensWithSignatures(
            allocator,
            options.source,
            config,
        );
    }

    if (args.tx_build_auto_gas_payment) {
        return try rpc.buildCommandSourceExecutePayloadWithAutoGasPaymentFromDefaultKeystore(
            allocator,
            options.source,
            config,
            args.tx_build_gas_payment_min_balance,
            .{
                .signer_selectors = args.signers.items,
                .from_keystore = args.from_keystore,
                .infer_sender_from_signers = true,
            },
        );
    }

    return try rpc.buildCommandSourceExecutePayloadResolvingSelectedArgumentTokensFromDefaultKeystore(
        allocator,
        options.source,
        config,
        .{
            .signer_selectors = args.signers.items,
            .from_keystore = args.from_keystore,
            .infer_sender_from_signers = true,
        },
    );
}

fn buildUnsafeCommandSourceTxBytes(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) ![]u8 {
    const sender = try resolvedUnsafeMoveCallSender(allocator, rpc, args) orelse return error.InvalidCli;
    defer allocator.free(sender);

    var owned_source = try resolvedUnsafeCommandSource(allocator, rpc, args, sender);
    defer owned_source.deinit(allocator);

    const gas_object_id = try resolvedUnsafeMoveCallGasObjectId(allocator, rpc, args, sender);
    defer if (gas_object_id) |value| allocator.free(value);

    return try rpc.buildCommandSourceTxBytes(
        allocator,
        sender,
        owned_source.source,
        gas_object_id,
        args.tx_build_gas_budget orelse return error.InvalidCli,
    );
}

fn buildLocalCommandSourceExecutePayload(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
) !?[]u8 {
    const allow_reference_gas_price_fallback = if (provider) |value|
        allowReferenceGasPriceFallbackForLocalProviderPath(value)
    else
        allowReferenceGasPriceFallbackForLocalSignerPath(args);

    var local = try ownLocalCommandSourceBuildContext(
        allocator,
        rpc,
        args,
        provider,
        true,
        allow_reference_gas_price_fallback,
        false,
    ) orelse return null;
    defer local.deinit(allocator);

    if (args.signatures.items.len != 0) {
        return try rpc.buildLocalProgrammableTransactionExecutePayloadFromCommandSourceWithSignatures(
            allocator,
            local.source,
            local.sender,
            local.gas_payment_json,
            local.gas_price,
            local.gas_budget,
            null,
            args.signatures.items,
            args.tx_options,
        );
    }

    if (provider) |value| {
        return rpc.buildLocalProgrammableTransactionExecutePayloadFromCommandSourceWithAccountProvider(
            allocator,
            local.source,
            local.sender,
            local.gas_payment_json,
            local.gas_price,
            local.gas_budget,
            null,
            args.tx_options,
            value,
        ) catch |err| switch (err) {
            error.UnsupportedAccountProvider => null,
            else => err,
        };
    }

    return try rpc.buildLocalProgrammableTransactionExecutePayloadFromCommandSourceFromDefaultKeystore(
        allocator,
        local.source,
        local.sender,
        local.gas_payment_json,
        local.gas_price,
        local.gas_budget,
        null,
        args.tx_options,
        .{
            .signer_selectors = args.signers.items,
            .from_keystore = args.from_keystore,
            .infer_sender_from_signers = true,
        },
    );
}

fn buildLocalCommandSourceTxBytes(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
) !?[]u8 {
    var local = try ownLocalCommandSourceBuildContext(
        allocator,
        rpc,
        args,
        provider,
        false,
        true,
        false,
    ) orelse return null;
    defer local.deinit(allocator);

    return try rpc.buildLocalProgrammableTransactionTxBytesFromCommandSource(
        allocator,
        local.source,
        local.sender,
        local.gas_payment_json,
        local.gas_price,
        local.gas_budget,
        null,
    );
}

const OwnedLocalCommandSourceBuildContext = struct {
    source: tx_builder.CommandSource,
    owned_source_json: ?[]u8 = null,
    sender: []const u8,
    gas_payment_json: []u8,
    gas_price: u64,
    gas_budget: u64,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.owned_source_json) |value| allocator.free(value);
        allocator.free(self.sender);
        allocator.free(self.gas_payment_json);
    }
};

fn ownLocalCommandSourceBuildContext(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
    require_signer_source: bool,
    allow_reference_gas_price_fallback: bool,
    allow_session_response: bool,
) !?OwnedLocalCommandSourceBuildContext {
    if (args.tx_session_response != null and !allow_session_response) return null;
    if (require_signer_source and !hasRealBuilderSignerSource(args) and provider == null) return null;
    if (!cli.supportsProgrammableInput(args)) return null;

    const requested_gas_budget = args.tx_build_gas_budget orelse if (args.tx_build_auto_gas_budget)
        provisional_auto_gas_budget
    else
        return null;
    const sender = blk: {
        if (try resolvedUnsafeMoveCallSender(allocator, rpc, args)) |value| break :blk value;
        if (provider) |value| {
            if (defaultSenderFromProgrammaticProvider(value)) |account_sender| {
                break :blk try allocator.dupe(u8, account_sender);
            }
        }
        return null;
    };
    _ = client.ptb_bytes_builder.parseHexAddress32(sender) catch {
        allocator.free(sender);
        return null;
    };
    errdefer allocator.free(sender);

    const gas_price = try rpc.resolveEffectiveGasPrice(
        args.tx_build_gas_price,
        allow_reference_gas_price_fallback,
    ) orelse {
        allocator.free(sender);
        return null;
    };

    var owned_source = try resolvedUnsafeCommandSource(allocator, rpc, args, sender);
    errdefer owned_source.deinit(allocator);
    if (!(try client.SuiRpcClient.commandSourceSupportsLocalProgrammableTransactionBuilder(
        allocator,
        owned_source.source,
    ))) {
        owned_source.deinit(allocator);
        allocator.free(sender);
        return null;
    }

    var excluded_object_ids = try rpc.ownReferencedObjectIdsFromCommandSource(
        allocator,
        owned_source.source,
    );
    defer excluded_object_ids.deinit(allocator);

    var gas_payment_json = try resolvedLocalBuilderGasPaymentJson(
        allocator,
        rpc,
        args,
        sender,
        requested_gas_budget,
        excluded_object_ids.items.items,
    ) orelse {
        owned_source.deinit(allocator);
        allocator.free(sender);
        return null;
    };
    errdefer allocator.free(gas_payment_json);

    var effective_gas_budget = requested_gas_budget;
    if (args.tx_build_auto_gas_budget) {
        const provisional_tx_bytes = try rpc.buildLocalProgrammableTransactionTxBytesFromCommandSource(
            allocator,
            owned_source.source,
            sender,
            gas_payment_json,
            gas_price,
            requested_gas_budget,
            null,
        );
        defer allocator.free(provisional_tx_bytes);

        const dry_run_payload = try tx_builder.buildDryRunPayload(allocator, provisional_tx_bytes);
        defer allocator.free(dry_run_payload);

        const dry_run_response = try rpc.sendTxDryRun(dry_run_payload);
        defer rpc.allocator.free(dry_run_response);

        var insights = try rpc.summarizeExecutionResponse(allocator, dry_run_response);
        defer insights.deinit(allocator);

        effective_gas_budget = try estimatedGasBudgetFromInsights(insights);
        if (args.tx_build_auto_gas_payment and effective_gas_budget != requested_gas_budget) {
            allocator.free(gas_payment_json);
            gas_payment_json = try resolvedLocalBuilderGasPaymentJson(
                allocator,
                rpc,
                args,
                sender,
                effective_gas_budget,
                excluded_object_ids.items.items,
            ) orelse {
                owned_source.deinit(allocator);
                allocator.free(sender);
                return null;
            };
        }
    }

    return .{
        .source = owned_source.source,
        .owned_source_json = owned_source.owned_json,
        .sender = sender,
        .gas_payment_json = gas_payment_json,
        .gas_price = gas_price,
        .gas_budget = effective_gas_budget,
    };
}

fn buildLocalCommandSourceTransactionBlock(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
) !?[]u8 {
    var local = try ownLocalCommandSourceBuildContext(
        allocator,
        rpc,
        args,
        provider,
        false,
        true,
        false,
    ) orelse return null;
    defer local.deinit(allocator);

    return try rpc.buildLocalProgrammableTransactionBlockFromCommandSource(
        allocator,
        local.source,
        local.sender,
        local.gas_payment_json,
        local.gas_price,
        local.gas_budget,
        null,
    );
}

fn buildLocalCommandSourceInspectPayload(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
) !?[]u8 {
    var local = try ownLocalCommandSourceBuildContext(
        allocator,
        rpc,
        args,
        provider,
        false,
        true,
        false,
    ) orelse return null;
    defer local.deinit(allocator);

    return try rpc.buildLocalProgrammableTransactionInspectPayloadFromCommandSource(
        allocator,
        local.source,
        local.sender,
        local.gas_payment_json,
        local.gas_price,
        local.gas_budget,
        null,
        args.tx_options,
    );
}

fn runLocalCommandSourceAction(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: client.tx_request_builder.AccountProvider,
    allow_reference_gas_price_fallback: bool,
    action: client.rpc_client.ProgrammaticClientAction,
) !?client.rpc_client.ProgrammaticClientActionOrChallengePromptResult {
    var local = ownLocalCommandSourceBuildContext(
        allocator,
        rpc,
        args,
        provider,
        true,
        allow_reference_gas_price_fallback,
        true,
    ) catch |err| switch (err) {
        error.InvalidCli => return null,
        else => return err,
    } orelse return null;
    defer local.deinit(allocator);

    var parsed_session_response: ?ParsedSessionChallengeResponse = null;
    defer if (parsed_session_response) |*value| value.deinit();
    if (args.tx_session_response) |raw| {
        parsed_session_response = try parseSessionChallengeResponseArg(allocator, raw);
    }

    if (parsed_session_response) |challenge_response| {
        return .{ .completed = rpc.runLocalProgrammableTransactionFromCommandSourceWithChallengeResponseWithAccountProvider(
            allocator,
            local.source,
            local.sender,
            local.gas_payment_json,
            local.gas_price,
            local.gas_budget,
            null,
            args.tx_options,
            provider,
            challenge_response.response,
            action,
        ) catch |err| switch (err) {
            error.InvalidCli => return null,
            else => return err,
        } };
    }

    return rpc.runLocalProgrammableTransactionFromCommandSourceOrChallengePromptWithAccountProvider(
        allocator,
        local.source,
        local.sender,
        local.gas_payment_json,
        local.gas_price,
        local.gas_budget,
        null,
        args.tx_options,
        provider,
        action,
    ) catch |err| switch (err) {
        error.InvalidCli => return null,
        else => return err,
    };
}

fn runUnsafeCommandSourceAction(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
    action: client.rpc_client.ProgrammaticClientAction,
) !client.rpc_client.ProgrammaticClientActionOrChallengePromptResult {
    var parsed_session_response: ?ParsedSessionChallengeResponse = null;
    defer if (parsed_session_response) |*value| value.deinit();
    if (args.tx_session_response) |raw| {
        parsed_session_response = try parseSessionChallengeResponseArg(allocator, raw);
    }

    const sender = blk: {
        if (try resolvedUnsafeMoveCallSender(allocator, rpc, args)) |value| break :blk value;
        if (provider) |value| {
            if (defaultSenderFromProgrammaticProvider(value)) |account_sender| {
                break :blk try allocator.dupe(u8, account_sender);
            }
        }
        return error.InvalidCli;
    };
    defer allocator.free(sender);

    const options = programmaticRequestOptionsFromArgs(args, args.signatures.items);
    const config = commandRequestConfigFromOptions(options, sender);

    if (parsed_session_response) |challenge_response| {
        if (args.signatures.items.len != 0 or hasKeystoreBackedSignerSource(args)) return error.InvalidCli;
        const effective_provider = provider orelse return error.InvalidCli;
        if (args.tx_build_auto_gas_payment) {
            return .{ .completed = try rpc.runCommandSourceWithAutoGasPaymentWithChallengeResponseWithAccountProvider(
                allocator,
                options.source,
                config,
                effective_provider,
                args.tx_build_gas_payment_min_balance,
                challenge_response.response,
                action,
            ) };
        }

        return .{ .completed = try rpc.runCommandSourceResolvingSelectedArgumentTokensWithChallengeResponseWithAccountProvider(
            allocator,
            options.source,
            config,
            effective_provider,
            challenge_response.response,
            action,
        ) };
    }

    if (args.signatures.items.len != 0) {
        if (args.tx_build_auto_gas_payment) {
            return .{ .completed = try rpc.runCommandSourceWithAutoGasPaymentWithSignatures(
                allocator,
                options.source,
                config,
                args.tx_build_gas_payment_min_balance,
                action,
            ) };
        }
        return .{ .completed = try rpc.runCommandSourceResolvingSelectedArgumentTokensWithSignatures(
            allocator,
            options.source,
            config,
            action,
        ) };
    }

    if (hasKeystoreBackedSignerSource(args)) {
        if (args.tx_build_auto_gas_payment) {
            return .{ .completed = try rpc.runCommandSourceWithAutoGasPaymentFromDefaultKeystore(
                allocator,
                options.source,
                config,
                args.tx_build_gas_payment_min_balance,
                .{
                    .signer_selectors = args.signers.items,
                    .from_keystore = args.from_keystore,
                    .infer_sender_from_signers = true,
                },
                action,
            ) };
        }

        return .{ .completed = try rpc.runCommandSourceResolvingSelectedArgumentTokensFromDefaultKeystore(
            allocator,
            options.source,
            config,
            .{
                .signer_selectors = args.signers.items,
                .from_keystore = args.from_keystore,
                .infer_sender_from_signers = true,
            },
            action,
        ) };
    }

    const effective_provider = provider orelse return error.InvalidCli;
    if (args.tx_build_auto_gas_payment) {
        return try rpc.runCommandSourceWithAutoGasPaymentOrChallengePromptWithAccountProvider(
            allocator,
            options.source,
            config,
            effective_provider,
            args.tx_build_gas_payment_min_balance,
            action,
        );
    }

    return try rpc.runCommandSourceResolvingSelectedArgumentTokensOrChallengePromptWithAccountProvider(
        allocator,
        options.source,
        config,
        effective_provider,
        action,
    );
}

fn shouldUseUnsafeTransactionBuilderPathWithProvider(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    provider_available: bool,
) !bool {
    if (!provider_available) return false;
    if (!cli.supportsProgrammableInput(args)) return false;
    if (args.tx_build_gas_budget == null) return false;

    const supports_real_builder = try client.SuiRpcClient.commandSourceSupportsUnsafeTransactionBuilder(
        allocator,
        commandSourceFromArgs(args),
    );
    if (!supports_real_builder) return false;

    if (args.tx_build_sender != null) return true;

    const needs_real_builder_resolution = args.tx_build_auto_gas_payment or
        (try hasSelectedMoveCallArgumentRequests(allocator, args)) or
        programmaticCommandsContainSelectedRequestTokens(args) or
        gasPaymentContainsSelectedRequestToken(args);
    return needs_real_builder_resolution;
}

fn printProgrammaticActionResult(
    allocator: std.mem.Allocator,
    writer: anytype,
    result: client.rpc_client.ProgrammaticClientActionResult,
    pretty: bool,
) !void {
    switch (result) {
        .authorized => |value| {
            var authorized = value;
            const payload = try authorized.buildExecutePayload(allocator);
            defer allocator.free(payload);
            try printResponse(allocator, writer, payload, pretty);
        },
        .inspected => |value| try printResponse(allocator, writer, value, pretty),
        .inspect_summarized => |value| try printStructuredJson(writer, value, pretty),
        .executed => |value| try printResponse(allocator, writer, value, pretty),
        .summarized => |value| try printStructuredJson(writer, value, pretty),
        .observed => |value| try printStructuredJson(writer, value, pretty),
        .artifact => |value| try printResponse(allocator, writer, value, pretty),
        .artifact_summarized => |value| switch (value) {
            .transaction_block => |summary| try printStructuredJson(writer, summary, pretty),
            .inspect_payload => |summary| try printStructuredJson(writer, summary, pretty),
            .execute_payload => |summary| try printStructuredJson(writer, summary, pretty),
        },
    }
}

fn printProgrammaticActionOrChallengePromptResult(
    allocator: std.mem.Allocator,
    writer: anytype,
    result: client.rpc_client.ProgrammaticClientActionOrChallengePromptResult,
    pretty: bool,
) !void {
    switch (result) {
        .challenge_required => |value| try printStructuredJson(writer, value, pretty),
        .completed => |value| try printProgrammaticActionResult(allocator, writer, value, pretty),
    }
}

fn buildUnsafeBatchExecutePayloadFromDefaultKeystore(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
) ![]u8 {
    const sender = try resolvedUnsafeMoveCallSender(allocator, rpc, args) orelse return error.InvalidCli;
    defer allocator.free(sender);

    const maybe_resolved_commands_json = try rpc.resolveSelectedArgumentTokensInCommandSourceWithDefaultOwner(
        allocator,
        commandSourceFromArgs(args),
        sender,
    );
    defer if (maybe_resolved_commands_json) |value| allocator.free(value);
    const resolved_commands_json = maybe_resolved_commands_json orelse try tx_builder.resolveCommands(
        allocator,
        commandSourceFromArgs(args),
    );
    defer if (maybe_resolved_commands_json == null) allocator.free(resolved_commands_json);

    const gas_object_id = try resolvedUnsafeMoveCallGasObjectId(allocator, rpc, args, sender);
    defer if (gas_object_id) |value| allocator.free(value);

    const tx_bytes = try rpc.buildBatchTransactionTxBytes(
        allocator,
        sender,
        resolved_commands_json,
        gas_object_id,
        args.tx_build_gas_budget orelse return error.InvalidCli,
    );
    defer allocator.free(tx_bytes);

    return try buildUnsafeSignedExecutePayloadFromDefaultKeystoreTxBytes(allocator, args, tx_bytes);
}

fn runProgrammaticActionMaybeAutoGasPayment(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?client.tx_request_builder.AccountProvider,
    action: client.rpc_client.ProgrammaticClientAction,
) !client.rpc_client.ProgrammaticClientActionResult {
    const has_selected_requests = (try hasSelectedMoveCallArgumentRequests(allocator, args)) or
        programmaticCommandsContainSelectedRequestTokens(args) or
        gasPaymentContainsSelectedRequestToken(args);
    if (has_selected_requests) {
        return try runSelectedProgrammaticAction(allocator, rpc, args, signatures, provider, action);
    }
    if (args.tx_build_auto_gas_payment) {
        return try rpc.runOptionsWithAutoGasPaymentWithAccountProvider(
            allocator,
            programmaticRequestOptionsFromArgs(args, signatures),
            provider orelse .none,
            args.tx_build_gas_payment_min_balance,
            action,
        );
    }
    return try rpc.runPlan(
        allocator,
        programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, provider),
        action,
    );
}

fn runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?client.tx_request_builder.AccountProvider,
    action: client.rpc_client.ProgrammaticClientAction,
) !client.rpc_client.ProgrammaticClientActionOrChallengePromptResult {
    var parsed_session_response: ?ParsedSessionChallengeResponse = null;
    defer if (parsed_session_response) |*value| value.deinit();
    if (args.tx_session_response) |raw| {
        parsed_session_response = try parseSessionChallengeResponseArg(allocator, raw);
    }

    const effective_provider = provider orelse {
        if (parsed_session_response != null) return error.InvalidCli;
        return .{ .completed = try runProgrammaticActionMaybeAutoGasPayment(
            allocator,
            rpc,
            args,
            signatures,
            null,
            action,
        ) };
    };

    const has_selected_requests = (try hasSelectedMoveCallArgumentRequests(allocator, args)) or
        programmaticCommandsContainSelectedRequestTokens(args) or
        gasPaymentContainsSelectedRequestToken(args);

    if (has_selected_requests) {
        const options = programmaticRequestOptionsFromArgs(args, signatures);
        const resolved_sender = try resolvedTxBuildSenderFromArgs(allocator, args);
        defer if (resolved_sender) |value| allocator.free(value);
        const config = commandRequestConfigFromOptions(options, resolved_sender);

        if (parsed_session_response) |challenge_response| {
            if (args.tx_build_auto_gas_payment) {
                return .{ .completed = try rpc.runCommandsWithAutoGasPaymentWithChallengeResponseWithAccountProvider(
                    allocator,
                    options.source,
                    config,
                    effective_provider,
                    args.tx_build_gas_payment_min_balance,
                    challenge_response.response,
                    action,
                ) };
            }

            return .{ .completed = try rpc.runCommandsResolvingSelectedArgumentTokensWithChallengeResponseWithAccountProvider(
                allocator,
                options.source,
                config,
                effective_provider,
                challenge_response.response,
                action,
            ) };
        }

        if (args.tx_build_auto_gas_payment) {
            return try rpc.runCommandsWithAutoGasPaymentOrChallengePromptWithAccountProvider(
                allocator,
                options.source,
                config,
                effective_provider,
                args.tx_build_gas_payment_min_balance,
                action,
            );
        }

        return try rpc.runCommandsResolvingSelectedArgumentTokensOrChallengePromptWithAccountProvider(
            allocator,
            options.source,
            config,
            effective_provider,
            action,
        );
    }

    if (args.tx_build_auto_gas_payment) {
        if (parsed_session_response) |challenge_response| {
            return .{ .completed = try rpc.runOptionsWithAutoGasPaymentWithChallengeResponseWithAccountProvider(
                allocator,
                programmaticRequestOptionsFromArgs(args, signatures),
                effective_provider,
                args.tx_build_gas_payment_min_balance,
                challenge_response.response,
                action,
            ) };
        }

        return try rpc.runOptionsWithAutoGasPaymentOrChallengePromptWithAccountProvider(
            allocator,
            programmaticRequestOptionsFromArgs(args, signatures),
            effective_provider,
            args.tx_build_gas_payment_min_balance,
            action,
        );
    }

    if (parsed_session_response) |challenge_response| {
        return .{ .completed = try rpc.runPlanWithChallengeResponse(
            allocator,
            programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, effective_provider),
            challenge_response.response,
            action,
        ) };
    }

    return try rpc.runPlanOrChallengePrompt(
        allocator,
        programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, effective_provider),
        action,
    );
}

fn writeOptionalJsonArray(
    allocator: std.mem.Allocator,
    writer: anytype,
    raw: ?[]const u8,
) !void {
    const value = raw orelse "[]";
    const trimmed = std.mem.trim(u8, value, " \n\r\t");
    if (trimmed.len == 0) {
        try writer.writeAll("[]");
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidCli;
    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
}

fn writeMoveCallInstruction(
    allocator: std.mem.Allocator,
    writer: anytype,
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    type_args: ?[]const u8,
    call_args: ?[]const u8,
) !void {
    try tx_builder.writeMoveCallInstruction(allocator, writer, package_id, module, function_name, type_args, call_args);
}

fn resolveProgrammaticCommandsFromArgs(
    allocator: std.mem.Allocator,
    command_items: []const []const u8,
    commands_json: ?[]const u8,
    package_id: ?[]const u8,
    module: ?[]const u8,
    function_name: ?[]const u8,
    type_args: ?[]const u8,
    args: ?[]const u8,
) ![]u8 {
    return try tx_builder.resolveCommands(allocator, .{
        .command_items = command_items,
        .commands_json = commands_json,
        .move_call = if (package_id != null and module != null and function_name != null)
            .{
                .package_id = package_id.?,
                .module = module.?,
                .function_name = function_name.?,
                .type_args = type_args,
                .arguments = args,
            }
        else
            null,
    });
}

fn appendNormalizedCommandJson(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    out: *std.ArrayList(u8),
    has_output: *bool,
) !void {
    const normalized = try normalizeProgrammaticCommandsFromArgs(allocator, commands_json);
    defer allocator.free(normalized);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized, .{});
    defer parsed.deinit();

    for (parsed.value.array.items) |entry| {
        if (has_output.*) {
            try out.append(allocator, ',');
        }
        const writer = out.writer(allocator);
        try writer.print("{f}", .{std.json.fmt(entry, .{})});
        has_output.* = true;
    }
}

fn normalizeProgrammaticCommandsFromArgs(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, commands_json, " \n\r\t");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    switch (parsed.value) {
        .array => |array| {
            if (array.items.len == 0) return error.InvalidCli;
            for (array.items) |entry| {
                validateProgrammaticCommandEntry(entry) catch |err| switch (err) {
                    error.InvalidCli => return error.InvalidCli,
                    else => return err,
                };
            }
            return try allocator.dupe(u8, trimmed);
        },
        .object => {
            validateProgrammaticCommandEntry(parsed.value) catch |err| switch (err) {
                error.InvalidCli => return error.InvalidCli,
                else => return err,
            };

            var out = std.ArrayList(u8){};
            errdefer out.deinit(allocator);
            const writer = out.writer(allocator);
            try writer.writeAll("[");
            try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
            try writer.writeAll("]");
            return out.toOwnedSlice(allocator);
        },
        else => return error.InvalidCli,
    }
}

fn validateProgrammaticCommandEntry(entry: std.json.Value) !void {
    try tx_builder.validateCommandEntry(entry);
}

fn hasTxBuildMoveCallArgs(parsed: *const cli.ParsedArgs) bool {
    return parsed.tx_build_package != null or
        parsed.tx_build_module != null or
        parsed.tx_build_function != null or
        parsed.tx_build_type_args != null or
        parsed.tx_build_args != null;
}

fn hasCompleteTxBuildMoveCallArgs(parsed: *const cli.ParsedArgs) bool {
    return parsed.tx_build_package != null and
        parsed.tx_build_module != null and
        parsed.tx_build_function != null;
}

fn hasTxBuildProgrammaticCommands(parsed: *const cli.ParsedArgs) bool {
    return parsed.tx_build_commands != null or parsed.tx_build_command_items.items.len > 0;
}

fn validateTxBuildArguments(args: *const cli.ParsedArgs) !void {
    switch (args.tx_build_kind orelse return error.InvalidCli) {
        .move_call => {
            if (hasTxBuildProgrammaticCommands(args)) return error.InvalidCli;
            if (!hasCompleteTxBuildMoveCallArgs(args)) return error.InvalidCli;
        },
        .programmable => {
            if (hasTxBuildMoveCallArgs(args)) return error.InvalidCli;
            if (!hasTxBuildProgrammaticCommands(args)) return error.InvalidCli;
        },
    }
}

const TxInspectPayload = []const u8;
const TxExecutePayload = []const u8;

fn buildInspectPayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !TxInspectPayload {
    return try @import("./tx_pipeline.zig").buildInspectPayloadFromArgs(allocator, args);
}

fn buildExecutePayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    non_programmatic_default: ?[]const u8,
) !TxExecutePayload {
    return try @import("./tx_pipeline.zig").buildExecutePayloadFromArgs(
        allocator,
        args,
        signatures,
        non_programmatic_default,
    );
}

fn commandSourceFromArgs(args: *const cli.ParsedArgs) tx_builder.CommandSource {
    return @import("./tx_pipeline.zig").commandSourceFromArgs(args);
}

fn programmaticRequestOptionsFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) client.tx_request_builder.ProgrammaticRequestOptions {
    return @import("./tx_pipeline.zig").programmaticRequestOptionsFromArgs(args, signatures);
}

fn programmaticAuthorizationPlanFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) client.tx_request_builder.AuthorizationPlan {
    return @import("./tx_pipeline.zig").programmaticAuthorizationPlanFromArgs(args, signatures);
}

fn programmaticAuthorizationPlanFromArgsWithAccountProvider(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?client.tx_request_builder.AccountProvider,
) client.tx_request_builder.AuthorizationPlan {
    return @import("./tx_pipeline.zig").programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, provider);
}

fn resolvedProgrammaticProvider(
    args: *const cli.ParsedArgs,
    provider: ?client.tx_request_builder.AccountProvider,
) ?client.tx_request_builder.AccountProvider {
    return provider orelse @import("./tx_pipeline.zig").defaultProgrammaticAccountProviderFromArgs(args);
}

fn resolvedTxBuildSenderFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !?[]const u8 {
    return try @import("./tx_pipeline.zig").resolvedTxBuildSenderFromArgs(allocator, args);
}

fn buildTxBuildTransactionBlockFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) ![]u8 {
    return try @import("./tx_pipeline.zig").buildTxBuildTransactionBlockFromArgs(allocator, args);
}

fn buildTxBuildInstructionFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) ![]u8 {
    return try @import("./tx_pipeline.zig").buildTxBuildInstructionFromArgs(allocator, args);
}

fn buildExecutePayload(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    signatures: []const []const u8,
    options_json: ?[]const u8,
) ![]u8 {
    return try tx_builder.buildExecutePayload(allocator, tx_bytes, signatures, options_json);
}

fn buildProgrammaticTxExecutePayload(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    signatures: []const []const u8,
    options_json: ?[]const u8,
) ![]u8 {
    return try tx_builder.buildProgrammaticTxExecutePayload(
        allocator,
        commands_json,
        sender,
        gas_budget,
        gas_price,
        null,
        signatures,
        options_json,
    );
}

fn buildProgrammaticTxSimulatePayload(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    options_json: ?[]const u8,
) ![]u8 {
    return try tx_builder.buildProgrammaticTxSimulatePayload(
        allocator,
        commands_json,
        sender,
        gas_budget,
        gas_price,
        null,
        options_json,
    );
}

fn objectDataOptionsFromArgs(args: *const cli.ParsedArgs) client.rpc_client.ObjectDataOptions {
    return .{
        .show_type = args.object_show_type,
        .show_owner = args.object_show_owner,
        .show_previous_transaction = args.object_show_previous_transaction,
        .show_display = args.object_show_display,
        .show_content = args.object_show_content,
        .show_bcs = args.object_show_bcs,
        .show_storage_rebate = args.object_show_storage_rebate,
    };
}

fn hasTypedObjectDataOptions(args: *const cli.ParsedArgs) bool {
    return args.object_show_type or
        args.object_show_owner or
        args.object_show_previous_transaction or
        args.object_show_display or
        args.object_show_content or
        args.object_show_bcs or
        args.object_show_storage_rebate;
}

fn dynamicFieldNameFromArgs(args: *const cli.ParsedArgs) ?client.rpc_client.DynamicFieldName {
    const type_name = args.object_dynamic_field_name_type orelse return null;
    const value_json = args.object_dynamic_field_name_value orelse return null;
    return .{
        .type_name = type_name,
        .value_json = value_json,
    };
}

fn dynamicFieldPageRequestFromArgs(args: *const cli.ParsedArgs) client.rpc_client.DynamicFieldPageRequest {
    return .{
        .cursor = args.object_dynamic_fields_cursor,
        .limit = args.object_dynamic_fields_limit,
    };
}

fn objectReadOptionsFromArgs(args: *const cli.ParsedArgs) client.rpc_client.ObjectReadOptions {
    if (hasTypedObjectDataOptions(args)) {
        return .{ .typed = objectDataOptionsFromArgs(args) };
    }
    if (args.object_options) |options_json| {
        return .{ .json = options_json };
    }
    return .none;
}

fn ownedObjectsFilterFromArgs(args: *const cli.ParsedArgs) client.rpc_client.OwnedObjectsFilter {
    if (args.account_objects_module) |module_name| {
        return .{
            .move_module = .{
                .package = args.account_objects_package orelse return .none,
                .module = module_name,
            },
        };
    }
    if (args.account_objects_package) |package_id| {
        return .{ .package = package_id };
    }
    if (args.account_objects_object_id) |object_id| {
        return .{ .object_id = object_id };
    }
    if (args.account_objects_struct_type) |value| {
        return .{ .struct_type = value };
    }
    if (args.account_objects_filter) |value| {
        return .{ .json = value };
    }
    return .none;
}

fn resourceQueryFromArgs(
    args: *const cli.ParsedArgs,
    owner: []const u8,
) !client.rpc_client.ResourceQuery {
    return switch (args.command) {
        .account_coins => .{
            .coins = if (args.account_coins_all)
                .{
                    .all = .{
                        .owner = owner,
                        .request = .{
                            .coin_type = args.account_coin_type,
                            .cursor = args.account_coins_cursor,
                            .limit = args.account_coins_limit,
                        },
                    },
                }
            else
                .{
                    .page = .{
                        .owner = owner,
                        .request = .{
                            .coin_type = args.account_coin_type,
                            .cursor = args.account_coins_cursor,
                            .limit = args.account_coins_limit,
                        },
                    },
                },
        },
        .account_objects => .{
            .owned_objects = if (args.account_objects_all)
                .{
                    .all = .{
                        .owner = owner,
                        .request = .{
                            .filter = ownedObjectsFilterFromArgs(args),
                            .options = objectReadOptionsFromArgs(args),
                            .cursor = args.account_objects_cursor,
                            .limit = args.account_objects_limit,
                        },
                    },
                }
            else
                .{
                    .page = .{
                        .owner = owner,
                        .request = .{
                            .filter = ownedObjectsFilterFromArgs(args),
                            .options = objectReadOptionsFromArgs(args),
                            .cursor = args.account_objects_cursor,
                            .limit = args.account_objects_limit,
                        },
                    },
                },
        },
        else => return error.InvalidCli,
    };
}

fn objectQueryFromArgs(args: *const cli.ParsedArgs) !client.rpc_client.ObjectQuery {
    return switch (args.command) {
        .object_get => .{
            .get = .{
                .object_id = args.object_id orelse return error.InvalidCli,
                .options = objectReadOptionsFromArgs(args),
            },
        },
        .object_dynamic_fields => if (args.object_dynamic_fields_all)
            .{
                .dynamic_fields_all = .{
                    .parent_object_id = args.object_parent_id orelse return error.InvalidCli,
                    .request = dynamicFieldPageRequestFromArgs(args),
                },
            }
        else
            .{
                .dynamic_fields_page = .{
                    .parent_object_id = args.object_parent_id orelse return error.InvalidCli,
                    .request = dynamicFieldPageRequestFromArgs(args),
                },
            },
        .object_dynamic_field_object => .{
            .dynamic_field_object = .{
                .parent_object_id = args.object_parent_id orelse return error.InvalidCli,
                .name = if (dynamicFieldNameFromArgs(args)) |typed_name|
                    .{ .typed = typed_name }
                else
                    .{ .json = args.object_dynamic_field_name orelse return error.InvalidCli },
            },
        },
        else => return error.InvalidCli,
    };
}

fn objectQueryActionFromArgs(args: *const cli.ParsedArgs) client.rpc_client.ObjectQueryAction {
    return if (args.tx_send_summarize) .summarize else .raw;
}

fn eventFilterFromArgs(args: *const cli.ParsedArgs) client.rpc_client.EventFilter {
    if (args.event_module) |module_name| {
        return .{
            .move_module = .{
                .package = args.event_package orelse return .none,
                .module = module_name,
            },
        };
    }
    if (args.event_type) |type_name| {
        return .{ .move_event_type = type_name };
    }
    if (args.event_sender) |sender| {
        return .{ .sender = sender };
    }
    if (args.event_tx_digest_filter) |digest| {
        return .{ .transaction = digest };
    }
    if (args.event_filter) |filter_json| {
        return .{ .json = filter_json };
    }
    return .none;
}

fn eventQueryFromArgs(args: *const cli.ParsedArgs) client.rpc_client.EventQuery {
    const request: client.rpc_client.EventPageRequest = .{
        .filter = eventFilterFromArgs(args),
        .cursor_tx_digest = args.event_cursor_tx_digest,
        .cursor_event_seq = args.event_cursor_event_seq,
        .limit = args.event_limit,
        .descending_order = args.event_descending,
    };
    return if (args.event_all)
        .{ .all = .{ .request = request } }
    else
        .{ .page = .{ .request = request } };
}

fn moveQueryFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !client.rpc_client.MoveQuery {
    return switch (args.command) {
        .move_package => .{
            .package = .{
                .package_id = args.move_package orelse return error.InvalidCli,
            },
        },
        .move_module => .{
            .module = .{
                .package_id = args.move_package orelse return error.InvalidCli,
                .module = args.move_module orelse return error.InvalidCli,
            },
        },
        .move_function => .{
            .function = .{
                .package_id = args.move_package orelse return error.InvalidCli,
                .module = args.move_module orelse return error.InvalidCli,
                .function_name = args.move_function orelse return error.InvalidCli,
                .type_arguments_json = args.tx_build_type_args,
                .arguments_json = if (args.tx_build_args) |value| try allocator.dupe(u8, value) else null,
                .indexed_arguments_json = if (args.move_function_indexed_args_json) |value| try allocator.dupe(u8, value) else null,
                .indexed_object_arguments_json = if (args.move_function_indexed_object_args_json) |value| try allocator.dupe(u8, value) else null,
                .owner_address = try resolvedTxBuildSenderFromArgs(allocator, args),
                .signer_selector = if (args.signers.items.len == 0)
                    null
                else
                    try allocator.dupe(u8, args.signers.items[0]),
            },
        },
        else => return error.InvalidCli,
    };
}

fn readQueryActionFromArgs(args: *const cli.ParsedArgs) client.rpc_client.ReadQueryAction {
    return switch (args.command) {
        .account_list => if (args.account_list_json) .raw else .summarize,
        .account_info => if (args.account_info_json) .raw else .summarize,
        .account_resources => if (args.account_resources_json) .raw else .summarize,
        .account_coins => if (args.account_coins_json) .raw else .summarize,
        .account_objects => if (args.account_objects_json) .raw else .summarize,
        .events => if (args.events_json) .raw else .summarize,
        else => blk: {
            if (args.tx_send_observe) break :blk .observe;
            if (args.tx_send_summarize) break :blk .summarize;
            break :blk .raw;
        },
    };
}

fn resourceQueryActionFromArgs(args: *const cli.ParsedArgs) client.rpc_client.ResourceQueryAction {
    return switch (args.command) {
        .account_coins => if (args.account_coins_json) .raw else .summarize,
        .account_objects => if (args.account_objects_json) .raw else .summarize,
        .account_resources => if (args.account_resources_json) .raw else .summarize,
        else => .summarize,
    };
}

fn readQueryFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !client.rpc_client.ReadQuery {
    return switch (args.command) {
        .account_list => .{
            .account = .list,
        },
        .account_info => .{
            .account = .{
                .info = args.account_selector orelse return error.InvalidCli,
            },
        },
        .events => .{
            .events = eventQueryFromArgs(args),
        },
        .move_package, .move_module, .move_function => .{
            .move = try moveQueryFromArgs(allocator, args),
        },
        .account_resources => return error.InvalidCli,
        .account_objects => return error.InvalidCli,
        .object_get, .object_dynamic_fields, .object_dynamic_field_object => .{
            .object = try objectQueryFromArgs(args),
        },
        .tx_status => .{
            .transaction_status = .{
                .digest = args.tx_digest orelse return error.InvalidCli,
            },
        },
        .tx_confirm => .{
            .transaction_confirm = .{
                .digest = args.tx_digest orelse return error.InvalidCli,
                .timeout_ms = args.confirm_timeout_ms orelse std.math.maxInt(u64),
                .poll_ms = args.confirm_poll_ms,
            },
        },
        else => return error.InvalidCli,
    };
}

fn resourceDiscoveryQueryFromArgs(
    args: *const cli.ParsedArgs,
    owner: []const u8,
) !client.rpc_client.ResourceDiscoveryQuery {
    return switch (args.command) {
        .account_resources => .{
            .coins = if (args.account_resources_all)
                .{
                    .all = .{
                        .owner = owner,
                        .request = .{
                            .coin_type = args.account_coin_type,
                            .limit = args.account_resources_limit,
                        },
                    },
                }
            else
                .{
                    .page = .{
                        .owner = owner,
                        .request = .{
                            .coin_type = args.account_coin_type,
                            .limit = args.account_resources_limit,
                        },
                    },
                },
            .owned_objects = if (args.account_resources_all)
                .{
                    .all = .{
                        .owner = owner,
                        .request = .{
                            .filter = ownedObjectsFilterFromArgs(args),
                            .options = objectReadOptionsFromArgs(args),
                            .limit = args.account_resources_limit,
                        },
                    },
                }
            else
                .{
                    .page = .{
                        .owner = owner,
                        .request = .{
                            .filter = ownedObjectsFilterFromArgs(args),
                            .options = objectReadOptionsFromArgs(args),
                            .limit = args.account_resources_limit,
                        },
                    },
                },
        },
        else => return error.InvalidCli,
    };
}

fn resolveAccountQueryOwner(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !struct { owner: []const u8, owned: ?[]const u8 } {
    const selector = args.account_selector orelse return error.InvalidCli;
    if (std.mem.startsWith(u8, selector, "0x")) {
        return .{ .owner = selector, .owned = null };
    }

    const resolved = try client.keystore.resolveAddressBySelector(allocator, selector) orelse return error.InvalidCli;
    return .{ .owner = resolved, .owned = resolved };
}

fn printAccountEntry(writer: anytype, entry: client.keystore.OwnedAccountEntry) !void {
    try writer.print("[{d}] selector=", .{entry.index});
    if (entry.selector) |selector| {
        try writer.print("{s}", .{selector});
    } else {
        try writer.print("<missing>", .{});
    }
    if (entry.alias) |alias| {
        try writer.print(" alias={s}", .{alias});
    }
    if (entry.name) |name| {
        try writer.print(" name={s}", .{name});
    }
    if (entry.address) |address| {
        try writer.print(" address={s}", .{address});
    }
    if (entry.sui_address) |sui_address| {
        try writer.print(" suiAddress={s}", .{sui_address});
    }
    if (entry.public_key) |public_key| {
        try writer.print(" publicKey={s}", .{public_key});
    }
    try writer.writeAll("\n");
}

fn printAccountEntries(writer: anytype, entries: []const client.keystore.OwnedAccountEntry) !void {
    if (entries.len == 0) {
        try writer.writeAll("No accounts found in keystore\n");
        return;
    }

    for (entries) |entry| {
        try printAccountEntry(writer, entry);
    }
}

fn printReadQuerySummary(
    writer: anytype,
    summary: client.rpc_client.ReadQuerySummary,
    pretty: bool,
) !void {
    switch (summary) {
        .account => |account| switch (account) {
            .list => |list| try printAccountEntries(writer, list.accounts),
            .info => |entry| try printAccountEntry(writer, entry),
        },
        .resources => |value| try printStructuredJson(writer, value, pretty),
        .coins => |value| try printStructuredJson(writer, value, pretty),
        .owned_objects => |value| try printStructuredJson(writer, value, pretty),
        .events => |value| try printStructuredJson(writer, value, pretty),
        .object => |object| switch (object) {
            .object => |value| try printStructuredJson(writer, value, pretty),
            .dynamic_fields => |value| try printStructuredJson(writer, value, pretty),
        },
        .move => |move| switch (move) {
            .function => |value| try printStructuredJson(writer, value, pretty),
            .module => |value| try printStructuredJson(writer, value, pretty),
            .package => |value| try printStructuredJson(writer, value, pretty),
        },
        .transaction => |value| try printStructuredJson(writer, value, pretty),
    }
}

fn printReadQueryActionResult(
    allocator: std.mem.Allocator,
    writer: anytype,
    result: client.rpc_client.ReadQueryActionResult,
    pretty: bool,
) !void {
    switch (result) {
        .raw => |response| try printResponse(allocator, writer, response, pretty),
        .summarized => |summary| try printReadQuerySummary(writer, summary, pretty),
        .observed => |observation| try printStructuredJson(writer, observation, pretty),
    }
}

fn printResourceQuerySummary(
    writer: anytype,
    summary: client.rpc_client.ResourceQuerySummary,
    pretty: bool,
) !void {
    switch (summary) {
        .coins => |value| try printStructuredJson(writer, value, pretty),
        .owned_objects => |value| try printStructuredJson(writer, value, pretty),
    }
}

fn printResourceQueryActionResult(
    allocator: std.mem.Allocator,
    writer: anytype,
    result: client.rpc_client.ResourceQueryActionResult,
    pretty: bool,
) !void {
    switch (result) {
        .raw => |response| try printResponse(allocator, writer, response, pretty),
        .summarized => |summary| try printResourceQuerySummary(writer, summary, pretty),
    }
}

pub fn runCommandWithProgrammaticProvider(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
    programmatic_provider: ?client.tx_request_builder.AccountProvider,
) !void {
    const effective_programmatic_provider = if (cli.supportsProgrammableInput(args))
        resolvedProgrammaticProvider(args, programmatic_provider)
    else
        null;

    switch (args.command) {
        .help => try cli.printUsage(writer),
        .version => {
            const version = @import("sui_client_zig").version;
            try writer.print("sui-zig-rpc-client {d}.{d}.{d}\n", .{ version.major, version.minor, version.patch });
        },
        .account_resources => {
            const resolved = try resolveAccountQueryOwner(allocator, args);
            defer if (resolved.owned) |value| allocator.free(value);

            var result = try rpc.runReadQueryAction(
                allocator,
                .{
                    .resources = try resourceDiscoveryQueryFromArgs(args, resolved.owner),
                },
                readQueryActionFromArgs(args),
            );
            defer result.deinit(allocator);
            try printReadQueryActionResult(allocator, writer, result, args.pretty);
        },
        .account_coins, .account_objects => {
            const resolved = try resolveAccountQueryOwner(allocator, args);
            defer if (resolved.owned) |value| allocator.free(value);

            var result = try rpc.runResourceQueryAction(
                allocator,
                try resourceQueryFromArgs(args, resolved.owner),
                resourceQueryActionFromArgs(args),
            );
            defer result.deinit(allocator);
            try printResourceQueryActionResult(allocator, writer, result, args.pretty);
        },
        .account_list, .account_info, .events, .move_package, .move_module, .move_function, .object_get, .object_dynamic_fields, .object_dynamic_field_object, .tx_status, .tx_confirm => {
            switch (args.command) {
                .tx_status, .tx_confirm => {
                    const digest = args.tx_digest orelse return error.InvalidCli;
                    if (std.mem.eql(u8, digest, "")) return error.InvalidCli;
                },
                else => {},
            }

            if (args.command == .move_function and
                (args.move_function_template_output != null or
                    args.move_function_execute_dry_run or
                    args.move_function_execute_send))
            {
                var query = try readQueryFromArgs(allocator, args);
                defer query.deinit(allocator);
                var result = try rpc.runReadQueryAction(
                    allocator,
                    query,
                    .summarize,
                );
                defer result.deinit(allocator);

                if (args.move_function_execute_dry_run or args.move_function_execute_send) {
                    const exec_command: cli.Command = if (args.move_function_execute_dry_run) .tx_dry_run else .tx_send;
                    const request_selection = try moveFunctionExecutionRequestArtifact(
                        allocator,
                        result,
                        exec_command,
                    );
                    var derived_args = try buildDerivedMoveFunctionExecutionArgs(
                        allocator,
                        args,
                        exec_command,
                        request_selection.request_json,
                    );
                    defer derived_args.deinit(allocator);
                    try runCommandWithProgrammaticProvider(
                        allocator,
                        rpc,
                        &derived_args,
                        writer,
                        effective_programmatic_provider,
                    );
                    return;
                }

                if (args.move_function_template_output) |output_kind| {
                    try printMoveFunctionTemplateOutput(writer, result, output_kind);
                    return;
                }
            }

            var query = try readQueryFromArgs(allocator, args);
            defer query.deinit(allocator);
            var result = try rpc.runReadQueryAction(
                allocator,
                query,
                readQueryActionFromArgs(args),
            );
            defer result.deinit(allocator);
            if (args.command == .move_function) {
                if (args.move_function_template_output) |output_kind| {
                    try printMoveFunctionTemplateOutput(writer, result, output_kind);
                    return;
                }
            }
            try printReadQueryActionResult(allocator, writer, result, args.pretty);
        },
        .rpc => {
            const method = args.method orelse return error.InvalidCli;
            const params = args.params orelse "[]";
            const response = try rpc.call(method, params);
            defer rpc.allocator.free(response);
            try printResponse(allocator, writer, response, args.pretty);
        },
        .tx_build => {
            const kind = args.tx_build_kind orelse return error.InvalidCli;
            try validateTxBuildArguments(args);
            if (args.tx_session_response != null and !args.tx_build_emit_tx_block) {
                return error.InvalidCli;
            }

            switch (kind) {
                .move_call => {
                    if (args.tx_build_emit_tx_block) {
                        if (try buildLocalCommandSourceTransactionBlock(allocator, rpc, args, effective_programmatic_provider)) |tx_block| {
                            defer allocator.free(tx_block);
                            if (args.tx_send_summarize) {
                                var summary = try rpc.summarizeBuildArtifact(allocator, tx_block);
                                defer summary.deinit(allocator);
                                try printStructuredJson(writer, summary, args.pretty);
                            } else {
                                try writer.print("{s}", .{tx_block});
                            }
                            return;
                        }
                    }
                    if (try hasSelectedMoveCallArgumentRequests(allocator, args)) {
                        if (args.tx_build_emit_tx_block) {
                            var result = try runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
                                allocator,
                                rpc,
                                args,
                                &.{},
                                effective_programmatic_provider,
                                if (args.tx_send_summarize)
                                    .{ .build_artifact_summarize = .transaction_block }
                                else
                                    .{ .build_artifact = .transaction_block },
                            );
                            defer result.deinit(allocator);
                            try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                        } else {
                            const instruction = try buildSelectedMoveCallInstructionFromArgs(allocator, rpc, args);
                            defer allocator.free(instruction);
                            if (args.tx_send_summarize) {
                                var summary = try rpc.summarizeBuildArtifact(allocator, instruction);
                                defer summary.deinit(allocator);
                                try printStructuredJson(writer, summary, args.pretty);
                            } else {
                                try writer.print("{s}\n", .{instruction});
                            }
                        }
                    } else if (args.tx_build_emit_tx_block and (args.tx_build_auto_gas_payment or gasPaymentContainsSelectedRequestToken(args))) {
                        var result = try runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
                            allocator,
                            rpc,
                            args,
                            &.{},
                            effective_programmatic_provider,
                            if (args.tx_send_summarize)
                                .{ .build_artifact_summarize = .transaction_block }
                            else
                                .{ .build_artifact = .transaction_block },
                        );
                        defer result.deinit(allocator);
                        try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                    } else if (args.tx_build_emit_tx_block) {
                        const tx_block = try buildTxBuildTransactionBlockFromArgs(allocator, args);
                        defer allocator.free(tx_block);
                        if (args.tx_send_summarize) {
                            var summary = try rpc.summarizeBuildArtifact(allocator, tx_block);
                            defer summary.deinit(allocator);
                            try printStructuredJson(writer, summary, args.pretty);
                        } else {
                            try writer.print("{s}", .{tx_block});
                        }
                    } else {
                        const instruction = try buildTxBuildInstructionFromArgs(allocator, args);
                        defer allocator.free(instruction);
                        if (args.tx_send_summarize) {
                            var summary = try rpc.summarizeBuildArtifact(allocator, instruction);
                            defer summary.deinit(allocator);
                            try printStructuredJson(writer, summary, args.pretty);
                        } else {
                            try writer.print("{s}\n", .{instruction});
                        }
                    }
                },
                .programmable => {
                    if (try buildLocalCommandSourceTransactionBlock(allocator, rpc, args, effective_programmatic_provider)) |tx_block| {
                        defer allocator.free(tx_block);
                        if (args.tx_send_summarize) {
                            var summary = try rpc.summarizeBuildArtifact(allocator, tx_block);
                            defer summary.deinit(allocator);
                            try printStructuredJson(writer, summary, args.pretty);
                        } else {
                            try writer.print("{s}", .{tx_block});
                        }
                        return;
                    }
                    if (programmaticCommandsContainSelectedRequestTokens(args) or args.tx_build_auto_gas_payment or gasPaymentContainsSelectedRequestToken(args)) {
                        var result = try runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
                            allocator,
                            rpc,
                            args,
                            &.{},
                            effective_programmatic_provider,
                            if (args.tx_send_summarize)
                                .{ .build_artifact_summarize = .transaction_block }
                            else
                                .{ .build_artifact = .transaction_block },
                        );
                        defer result.deinit(allocator);
                        try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                    } else {
                        const tx_block = try buildTxBuildTransactionBlockFromArgs(allocator, args);
                        defer allocator.free(tx_block);
                        if (args.tx_send_summarize) {
                            var summary = try rpc.summarizeBuildArtifact(allocator, tx_block);
                            defer summary.deinit(allocator);
                            try printStructuredJson(writer, summary, args.pretty);
                        } else {
                            try writer.print("{s}", .{tx_block});
                        }
                    }
                },
            }
        },
        .tx_simulate => {
            if (cli.supportsProgrammableInput(args)) {
                if (try buildLocalCommandSourceInspectPayload(allocator, rpc, args, effective_programmatic_provider)) |params| {
                    defer allocator.free(params);
                    const response = try rpc.sendTxInspect(params);
                    defer rpc.allocator.free(response);
                    if (args.tx_send_summarize) {
                        var insights = try rpc.summarizeInspectResponse(allocator, response);
                        defer insights.deinit(allocator);
                        try printStructuredJson(writer, insights, args.pretty);
                    } else {
                        try printResponse(allocator, writer, response, args.pretty);
                    }
                    return;
                }
                var result = try runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
                    allocator,
                    rpc,
                    args,
                    &.{},
                    effective_programmatic_provider,
                    if (args.tx_send_summarize) .inspect_summarize else .inspect,
                );
                defer result.deinit(allocator);
                try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                return;
            }
            const params = try buildInspectPayloadFromArgs(allocator, args);
            defer allocator.free(params);
            const response = try rpc.sendTxInspect(params);
            defer rpc.allocator.free(response);
            if (args.tx_send_summarize) {
                var insights = try rpc.summarizeInspectResponse(allocator, response);
                defer insights.deinit(allocator);
                try printStructuredJson(writer, insights, args.pretty);
            } else {
                try printResponse(allocator, writer, response, args.pretty);
            }
        },
        .tx_dry_run => {
            if (cli.supportsProgrammableInput(args)) {
                if (args.tx_bytes != null) return error.InvalidCli;
                if (try buildLocalCommandSourceTxBytes(allocator, rpc, args, effective_programmatic_provider)) |tx_bytes| {
                    defer allocator.free(tx_bytes);
                    try sendDryRunAndMaybeSummarize(allocator, rpc, args, tx_bytes, writer);
                    return;
                }

                const tx_bytes = try buildUnsafeCommandSourceTxBytes(allocator, rpc, args);
                defer allocator.free(tx_bytes);
                try sendDryRunAndMaybeSummarize(allocator, rpc, args, tx_bytes, writer);
                return;
            }

            const tx_bytes = args.tx_bytes orelse return error.InvalidCli;
            try sendDryRunAndMaybeSummarize(allocator, rpc, args, tx_bytes, writer);
        },
        .tx_payload => {
            const signatures = if (args.signatures.items.len > 0) args.signatures.items else &.{};
            if (cli.supportsProgrammableInput(args)) {
                if (args.tx_bytes != null) return error.InvalidCli;
                const local_payload_action = if (args.tx_send_summarize)
                    client.rpc_client.ProgrammaticClientAction{ .build_artifact_summarize = .execute_payload }
                else
                    client.rpc_client.ProgrammaticClientAction{ .build_artifact = .execute_payload };
                if (effective_programmatic_provider) |provider| {
                    if (try runLocalCommandSourceAction(
                        allocator,
                        rpc,
                        args,
                        provider,
                        allowReferenceGasPriceFallbackForLocalProviderPath(provider),
                        local_payload_action,
                    )) |local_result| {
                        var result = local_result;
                        defer result.deinit(allocator);
                        try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                        return;
                    }
                } else if (try buildLocalCommandSourceExecutePayload(allocator, rpc, args, null)) |payload| {
                    defer allocator.free(payload);
                    if (args.tx_send_summarize) {
                        var summarized = try rpc.summarizeArtifact(allocator, .execute_payload, payload);
                        defer summarized.deinit(allocator);
                        switch (summarized) {
                            .execute_payload => |summary| try printStructuredJson(writer, summary, args.pretty),
                            else => return error.InvalidResponse,
                        }
                    } else {
                        try printResponse(allocator, writer, payload, args.pretty);
                    }
                    return;
                }
                const provider_available = effective_programmatic_provider != null;
                const use_unsafe_transaction_builder_path = (try shouldUseUnsafeTransactionBuilderPath(allocator, args)) or
                    (try shouldUseUnsafeTransactionBuilderPathWithProvider(allocator, args, provider_available));
                if (use_unsafe_transaction_builder_path) {
                    var result = try runUnsafeCommandSourceAction(
                        allocator,
                        rpc,
                        args,
                        effective_programmatic_provider,
                        local_payload_action,
                    );
                    defer result.deinit(allocator);
                    try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                } else {
                    var result = try runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
                        allocator,
                        rpc,
                        args,
                        signatures,
                        effective_programmatic_provider,
                        local_payload_action,
                    );
                    defer result.deinit(allocator);
                    try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                }
            } else {
                const payload =
                    try buildExecutePayloadFromArgs(allocator, args, signatures, null);
                defer allocator.free(payload);
                if (args.tx_send_summarize) {
                    var summarized = try rpc.summarizeArtifact(allocator, .execute_payload, payload);
                    defer summarized.deinit(allocator);
                    switch (summarized) {
                        .execute_payload => |summary| try printStructuredJson(writer, summary, args.pretty),
                        else => return error.InvalidResponse,
                    }
                } else {
                    try printResponse(allocator, writer, payload, args.pretty);
                }
            }
        },
        .tx_send => {
            const provider_available = effective_programmatic_provider != null;
            const use_unsafe_transaction_builder_path = (try shouldUseUnsafeTransactionBuilderPath(allocator, args)) or
                (try shouldUseUnsafeTransactionBuilderPathWithProvider(allocator, args, provider_available));
            if (args.tx_session_response != null and effective_programmatic_provider == null and !use_unsafe_transaction_builder_path) {
                if (!provider_available) return error.InvalidCli;
            }
            const can_execute_without_direct_signatures = cli.supportsProgrammableInput(args) and
                (provider_available or hasKeystoreBackedSignerSource(args));
            if (args.signatures.items.len == 0 and !can_execute_without_direct_signatures) {
                return error.InvalidCli;
            }
            if (cli.supportsProgrammableInput(args)) {
                if (args.tx_bytes != null) return error.InvalidCli;
                const action = if (args.tx_send_observe)
                    client.rpc_client.ProgrammaticClientAction{ .execute_confirm_observe = .{
                        .timeout_ms = args.confirm_timeout_ms orelse std.math.maxInt(u64),
                        .poll_ms = args.confirm_poll_ms,
                    } }
                else if (args.tx_send_summarize)
                    if (args.tx_send_wait)
                        client.rpc_client.ProgrammaticClientAction{ .execute_confirm_summarize = .{
                            .timeout_ms = args.confirm_timeout_ms orelse std.math.maxInt(u64),
                            .poll_ms = args.confirm_poll_ms,
                        } }
                    else
                        .execute_summarize
                else if (args.tx_send_wait)
                    client.rpc_client.ProgrammaticClientAction{ .execute_confirm = .{
                        .timeout_ms = args.confirm_timeout_ms orelse std.math.maxInt(u64),
                        .poll_ms = args.confirm_poll_ms,
                    } }
                else
                    .execute;
                if (effective_programmatic_provider) |provider| {
                    if (try runLocalCommandSourceAction(allocator, rpc, args, provider, true, action)) |local_result| {
                        var result = local_result;
                        defer result.deinit(allocator);
                        try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                        return;
                    }
                } else if (try buildLocalCommandSourceExecutePayload(allocator, rpc, args, null)) |payload| {
                    defer allocator.free(payload);
                    try sendExecuteAndMaybeWaitForConfirmation(allocator, rpc, args, payload, writer);
                    return;
                }
                if (use_unsafe_transaction_builder_path) {
                    var result = try runUnsafeCommandSourceAction(allocator, rpc, args, effective_programmatic_provider, action);
                    defer result.deinit(allocator);
                    try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                    return;
                }
                var result = try runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt(
                    allocator,
                    rpc,
                    args,
                    args.signatures.items,
                    effective_programmatic_provider,
                    action,
                );
                defer result.deinit(allocator);
                try printProgrammaticActionOrChallengePromptResult(allocator, writer, result, args.pretty);
                return;
            }
            const payload = try buildExecutePayloadFromArgs(
                allocator,
                args,
                args.signatures.items,
                null,
            );
            defer allocator.free(payload);
            try sendExecuteAndMaybeWaitForConfirmation(allocator, rpc, args, payload, writer);
        },
    }
}

pub fn runCommand(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    return try runCommandWithProgrammaticProvider(allocator, rpc, args, writer, null);
}

test "runCommand tx_payload writes expected payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "AAABBB",
        .tx_options = "{\"skipChecks\":true}",
    };
    try args.signatures.append(allocator, "sig-a");
    try args.signatures.append(allocator, "sig-b");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    try runCommand(allocator, &rpc, &args, writer);
    try testing.expectEqualStrings("[\"AAABBB\",[\"sig-a\",\"sig-b\"],{\"skipChecks\":true}]\n", output.items);
}

test "runCommand tx_payload with raw tx bytes and --summarize prints payload summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "AAABBB",
        .tx_options = "{\"skipChecks\":true}",
        .tx_send_summarize = true,
    };
    try args.signatures.append(allocator, "sig-a");
    try args.signatures.append(allocator, "sig-b");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const summary = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer summary.deinit();
    try testing.expectEqualStrings("tx_bytes", summary.value.object.get("data_kind").?.string);
    try testing.expectEqual(@as(i64, 2), summary.value.object.get("signature_count").?.integer);
    try testing.expect(summary.value.object.get("has_options").?.bool);
}

test "runCommand tx_payload rejects non-object options for raw tx bytes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "AAABBB",
        .tx_options = "[\"skipChecks\"]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand help writes usage" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .help,
        .has_command = true,
    };
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "Usage:") != null);
}

test "runCommand events with summarized move-module filter prints event summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "suix_queryEvents"));
            std.debug.assert(std.mem.eql(
                u8,
                req.params_json,
                "[{\"MoveModule\":{\"package\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"module\":\"pool\"}},null,5,true]",
            ));
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xdigest\",\"eventSeq\":\"7\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"sender\":\"0xsender\",\"type\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3::pool::LiquidityAdded\",\"parsedJson\":{\"pool\":\"0xpool\"},\"timestampMs\":\"42\"}],\"nextCursor\":{\"txDigest\":\"0xnext\",\"eventSeq\":\"8\"},\"hasNextPage\":true}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "events",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
        "--limit",
        "5",
        "--descending",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const entries = parsed.value.object.get("entries").?.array.items;
    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expectEqualStrings("0xdigest", entries[0].object.get("tx_digest").?.string);
    try testing.expectEqual(@as(i64, 7), entries[0].object.get("event_seq").?.integer);
    try testing.expectEqualStrings("pool", entries[0].object.get("transaction_module").?.string);
    try testing.expectEqualStrings("{\"pool\":\"0xpool\"}", entries[0].object.get("parsed_json").?.string);
    try testing.expectEqualStrings("0xnext", parsed.value.object.get("next_cursor_tx_digest").?.string);
    try testing.expectEqual(@as(i64, 8), parsed.value.object.get("next_cursor_event_seq").?.integer);
    try testing.expect(parsed.value.object.get("has_next_page").?.bool);
}

test "runCommand move function with --summarize prints normalized function summary" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"pool\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"swap\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[\"Bool\"]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "pool",
        .move_function = "swap",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("0x2", parsed.value.object.get("package_id").?.string);
    try testing.expectEqualStrings("pool", parsed.value.object.get("module_name").?.string);
    try testing.expectEqualStrings("swap", parsed.value.object.get("function_name").?.string);
    try testing.expectEqualStrings("object", parsed.value.object.get("parameters").?.array.items[0].object.get("lowering_kind").?.string);
    try testing.expectEqualStrings("\"<arg0-object-id-or-select-token>\"", parsed.value.object.get("parameters").?.array.items[0].object.get("placeholder_json").?.string);
    try testing.expectEqualStrings("u64", parsed.value.object.get("parameters").?.array.items[1].object.get("lowering_kind").?.string);
    try testing.expectEqualStrings("0", parsed.value.object.get("parameters").?.array.items[1].object.get("placeholder_json").?.string);
    try testing.expectEqualStrings("runtime", parsed.value.object.get("parameters").?.array.items[2].object.get("lowering_kind").?.string);
    try testing.expect(parsed.value.object.get("parameters").?.array.items[2].object.get("omitted_from_explicit_args").?.bool);
    try testing.expectEqualStrings("Bool", parsed.value.object.get("returns").?.array.items[0].object.get("signature").?.string);
    try testing.expectEqualStrings("[]", parsed.value.object.get("call_template").?.object.get("type_args_json").?.string);
    try testing.expectEqualStrings("[\"<arg0-object-id-or-select-token>\",0]", parsed.value.object.get("call_template").?.object.get("args_json").?.string);
    try testing.expectEqualStrings(
        "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}",
        parsed.value.object.get("call_template").?.object.get("move_call_command_json").?.string,
    );
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}]",
        parsed.value.object.get("call_template").?.object.get("commands_json").?.string,
    );
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}],\"sender\":\"0x<sender>\",\"gasBudget\":100000000,\"gasPrice\":1000,\"autoGasPayment\":true,\"autoGasBudget\":true,\"summarize\":true}",
        parsed.value.object.get("call_template").?.object.get("tx_dry_run_request_json").?.string,
    );
    const dry_run_argv = parsed.value.object.get("call_template").?.object.get("tx_dry_run_argv").?.array.items;
    try testing.expectEqual(@as(usize, 19), dry_run_argv.len);
    try testing.expectEqualStrings("tx", dry_run_argv[0].string);
    try testing.expectEqualStrings("dry-run", dry_run_argv[1].string);
    try testing.expectEqualStrings("--package", dry_run_argv[2].string);
    try testing.expectEqualStrings("0x2", dry_run_argv[3].string);
    try testing.expectEqualStrings("--type-args", dry_run_argv[8].string);
    try testing.expectEqualStrings("[]", dry_run_argv[9].string);
    try testing.expectEqualStrings("--args", dry_run_argv[10].string);
    try testing.expectEqualStrings("[\"<arg0-object-id-or-select-token>\",0]", dry_run_argv[11].string);
    try testing.expectEqualStrings("0x<sender>", dry_run_argv[13].string);
    const send_argv = parsed.value.object.get("call_template").?.object.get("tx_send_from_keystore_argv").?.array.items;
    try testing.expectEqual(@as(usize, 20), send_argv.len);
    try testing.expectEqualStrings("tx", send_argv[0].string);
    try testing.expectEqualStrings("send", send_argv[1].string);
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}],\"fromKeystore\":true,\"signer\":\"<alias-or-address>\",\"gasBudget\":100000000,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}",
        parsed.value.object.get("call_template").?.object.get("tx_send_from_keystore_request_json").?.string,
    );
    try testing.expectEqualStrings("--from-keystore", send_argv[12].string);
    try testing.expectEqualStrings("<alias-or-address>", send_argv[14].string);
    try testing.expectEqualStrings("--auto-gas-payment", send_argv[17].string);
}

test "runCommand move function with --summarize applies sparse explicit pure args to preferred templates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "pool",
        .move_function = "swap",
        .tx_build_args = "[7]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings("7", parameters[1].object.get("explicit_arg_json").?.string);
    try testing.expectEqualStrings(
        "[\"<arg0-object-id-or-select-token>\",7]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize reports pure wrapper lowering kinds" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"pure_helpers\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"submit\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x1\",\"module\":\"string\",\"name\":\"String\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"object\",\"name\":\"ID\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x1\",\"module\":\"option\",\"name\":\"Option\",\"typeParams\":[\"U64\"]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[\"Bool\"]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "pure_helpers",
        .move_function = "submit",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("utf8_string", parsed.value.object.get("parameters").?.array.items[0].object.get("lowering_kind").?.string);
    try testing.expectEqualStrings("\"<arg0-utf8-string>\"", parsed.value.object.get("parameters").?.array.items[0].object.get("placeholder_json").?.string);
    try testing.expectEqualStrings("object_id", parsed.value.object.get("parameters").?.array.items[1].object.get("lowering_kind").?.string);
    try testing.expectEqualStrings("\"0x<arg1-object-id>\"", parsed.value.object.get("parameters").?.array.items[1].object.get("placeholder_json").?.string);
    try testing.expectEqualStrings("option", parsed.value.object.get("parameters").?.array.items[2].object.get("lowering_kind").?.string);
    try testing.expectEqualStrings("null", parsed.value.object.get("parameters").?.array.items[2].object.get("placeholder_json").?.string);
    try testing.expectEqualStrings("runtime", parsed.value.object.get("parameters").?.array.items[3].object.get("lowering_kind").?.string);
    try testing.expect(parsed.value.object.get("parameters").?.array.items[3].object.get("omitted_from_explicit_args").?.bool);
    try testing.expectEqualStrings("[\"<arg0-utf8-string>\",\"0x<arg1-object-id>\",null]", parsed.value.object.get("call_template").?.object.get("args_json").?.string);
    try testing.expectEqualStrings("[]", parsed.value.object.get("call_template").?.object.get("type_args_json").?.string);
}

test "runCommand move function with --summarize prefers known object preset tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"pool\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"add_liquidity_fix_coin\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[[],[]],\"parameters\":[{\"Reference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"config\",\"name\":\"GlobalConfig\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"clock\",\"name\":\"Clock\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "add_liquidity_fix_coin",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"cetus_clmm_global_config_mainnet\\\"}\"",
        parsed.value.object.get("parameters").?.array.items[0].object.get("placeholder_json").?.string,
    );
    const global_config_get_argv = parsed.value.object.get("parameters").?.array.items[0].object.get("object_get_argv").?.array.items;
    try testing.expectEqual(@as(usize, 4), global_config_get_argv.len);
    try testing.expectEqualStrings("object", global_config_get_argv[0].string);
    try testing.expectEqualStrings("get", global_config_get_argv[1].string);
    try testing.expectEqualStrings("cetus_clmm_global_config_mainnet", global_config_get_argv[2].string);
    try testing.expectEqualStrings("--summarize", global_config_get_argv[3].string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"clock\\\"}\"",
        parsed.value.object.get("parameters").?.array.items[1].object.get("placeholder_json").?.string,
    );
    const clock_get_argv = parsed.value.object.get("parameters").?.array.items[1].object.get("object_get_argv").?.array.items;
    try testing.expectEqual(@as(usize, 4), clock_get_argv.len);
    try testing.expectEqualStrings("object", clock_get_argv[0].string);
    try testing.expectEqualStrings("get", clock_get_argv[1].string);
    try testing.expectEqualStrings("clock", clock_get_argv[2].string);
    try testing.expectEqualStrings("--summarize", clock_get_argv[3].string);
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"cetus_clmm_global_config_mainnet\\\"}\",\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"clock\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("args_json").?.string,
    );
}

test "runCommand move function with --summarize adds owned object discovery templates for concrete object types" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"pool\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"add_liquidity_fix_coin\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"TypeParameter\":0},{\"TypeParameter\":1}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "add_liquidity_fix_coin",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqual(
        std.json.Value.null,
        parsed.value.object.get("parameters").?.array.items[0].object.get("owned_object_select_token").?,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x<arg0-object-id>\",\"inputKind\":\"shared\",\"mutable\":true}",
        parsed.value.object.get("parameters").?.array.items[0].object.get("shared_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x<arg0-object-id>\",\"inputKind\":\"imm_or_owned\"}",
        parsed.value.object.get("parameters").?.array.items[0].object.get("imm_or_owned_object_input_select_token").?.string,
    );
    try testing.expectEqual(
        std.json.Value.null,
        parsed.value.object.get("parameters").?.array.items[0].object.get("receiving_object_input_select_token").?,
    );
    const pool_get_argv = parsed.value.object.get("parameters").?.array.items[0].object.get("object_get_argv").?.array.items;
    try testing.expectEqual(@as(usize, 4), pool_get_argv.len);
    try testing.expectEqualStrings("object", pool_get_argv[0].string);
    try testing.expectEqualStrings("get", pool_get_argv[1].string);
    try testing.expectEqualStrings("0x<arg0-object-id>", pool_get_argv[2].string);
    try testing.expectEqualStrings("--summarize", pool_get_argv[3].string);
    try testing.expectEqual(
        std.json.Value.null,
        parsed.value.object.get("parameters").?.array.items[0].object.get("owned_object_query_argv").?,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x<arg1-object-id>\",\"inputKind\":\"shared\",\"mutable\":true}",
        parsed.value.object.get("parameters").?.array.items[1].object.get("shared_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x<arg1-object-id>\",\"inputKind\":\"imm_or_owned\"}",
        parsed.value.object.get("parameters").?.array.items[1].object.get("imm_or_owned_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"structType\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\"}",
        parsed.value.object.get("parameters").?.array.items[1].object.get("owned_object_select_token").?.string,
    );
    const position_get_argv = parsed.value.object.get("parameters").?.array.items[1].object.get("object_get_argv").?.array.items;
    try testing.expectEqual(@as(usize, 4), position_get_argv.len);
    try testing.expectEqualStrings("object", position_get_argv[0].string);
    try testing.expectEqualStrings("get", position_get_argv[1].string);
    try testing.expectEqualStrings("0x<arg1-object-id>", position_get_argv[2].string);
    try testing.expectEqualStrings("--summarize", position_get_argv[3].string);
    const position_query_argv = parsed.value.object.get("parameters").?.array.items[1].object.get("owned_object_query_argv").?.array.items;
    try testing.expectEqual(@as(usize, 6), position_query_argv.len);
    try testing.expectEqualStrings("account", position_query_argv[0].string);
    try testing.expectEqualStrings("objects", position_query_argv[1].string);
    try testing.expectEqualStrings("0x<owner>", position_query_argv[2].string);
    try testing.expectEqualStrings("--struct-type", position_query_argv[3].string);
    try testing.expectEqualStrings(
        "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position",
        position_query_argv[4].string,
    );
}

test "runCommand move function with --summarize fills owner context into owned object discovery templates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, ",20]") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "add_liquidity_fix_coin",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\"}",
        parameter.get("owned_object_select_token").?.string,
    );
    const owned_query_argv = parameter.get("owned_object_query_argv").?.array.items;
    try testing.expectEqualStrings("0xowner", owned_query_argv[2].string);
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), owned_candidates.len);
    try testing.expectEqualStrings("0xposition1", owned_candidates[0].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 7), owned_candidates[0].object.get("version").?.integer);
    try testing.expectEqualStrings("position-digest-1", owned_candidates[0].object.get("digest").?.string);
    try testing.expectEqualStrings(
        "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position",
        owned_candidates[0].object.get("type_name").?.string,
    );
    try testing.expectEqualStrings("0xowner", owned_candidates[0].object.get("owner_value").?.string);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xposition1\",\"inputKind\":\"imm_or_owned\",\"version\":7,\"digest\":\"position-digest-1\"}",
        owned_candidates[0].object.get("object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-1\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize caches initial owner discovery across identical owned params" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct {
        owned_object_requests: usize = 0,
    };

    var state = State{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const callback_state = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"},\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            callback_state.owned_object_requests += 1;
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::position::Position\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2a",
        .move_module = "router",
        .move_function = "double_redeem",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqual(@as(usize, 3), parameters.len);

    const first_owned_candidates = parameters[0].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), first_owned_candidates.len);
    try testing.expectEqualStrings("0xposition1", first_owned_candidates[0].object.get("object_id").?.string);

    const second_owned_candidates = parameters[1].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), second_owned_candidates.len);
    try testing.expectEqualStrings("0xposition1", second_owned_candidates[0].object.get("object_id").?.string);

    try testing.expectEqual(@as(usize, 1), state.owned_object_requests);
}

test "runCommand move function with --summarize discovers owned object candidates across owned-object pages" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var owned_request_count: usize = 0;

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const request_count = @as(*usize, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"3\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            request_count.* += 1;
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, ",20]") != null);

            if (request_count.* == 1) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ",null,20]") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"nextCursor\":\"cursor-next\",\"hasNextPage\":true}}",
                );
            }

            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"cursor-next\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"nextCursor\":null,\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "add_liquidity_fix_coin",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &owned_request_count,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), owned_request_count);
    try testing.expectEqual(@as(usize, 2), owned_candidates.len);
    try testing.expectEqualStrings("0xposition1", owned_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings("0xposition2", owned_candidates[1].object.get("object_id").?.string);
}

test "runCommand move function with --summarize discovers specialized generic owned objects from owner context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[[]],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"balance\",\"name\":\"Balance\",\"typeParams\":[{\"TypeParameter\":0}]}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xbalance1\"") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xbalance1\",\"version\":\"13\",\"digest\":\"balance-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"value\":\"9\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2::balance::Balance<0x2::sui::SUI>\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xbalance1\",\"version\":\"13\",\"digest\":\"balance-digest-1\",\"type\":\"0x2::balance::Balance<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "balance",
        "redeem",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::balance::Balance<0x2::sui::SUI>\"}",
        parameter.get("owned_object_select_token").?.string,
    );
    const owned_query_argv = parameter.get("owned_object_query_argv").?.array.items;
    try testing.expectEqual(@as(usize, 6), owned_query_argv.len);
    try testing.expectEqualStrings("account", owned_query_argv[0].string);
    try testing.expectEqualStrings("objects", owned_query_argv[1].string);
    try testing.expectEqualStrings("0xowner", owned_query_argv[2].string);
    try testing.expectEqualStrings("--struct-type", owned_query_argv[3].string);
    try testing.expectEqualStrings("0x2::balance::Balance<0x2::sui::SUI>", owned_query_argv[4].string);
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), owned_candidates.len);
    try testing.expectEqualStrings("0xbalance1", owned_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "0x2::balance::Balance<0x2::sui::SUI>",
        owned_candidates[0].object.get("type_name").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xbalance1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":13,\\\"digest\\\":\\\"balance-digest-1\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xbalance1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":13,\\\"digest\\\":\\\"balance-digest-1\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize links owned object candidates to selected shared objects" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-match\",\"version\":\"7\",\"digest\":\"position-digest-match\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-other\",\"version\":\"8\",\"digest\":\"position-digest-other\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-match\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-match\",\"version\":\"7\",\"digest\":\"position-digest-match\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"liquidity\":\"9\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-other\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-other\",\"version\":\"8\",\"digest\":\"position-digest-other\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\",\"liquidity\":\"3\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "add_liquidity_fix_coin",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-match\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-match\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-match\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-match\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize jointly selects shared and owned candidates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-match\",\"version\":\"7\",\"digest\":\"position-digest-match\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-other\",\"version\":\"8\",\"digest\":\"position-digest-other\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-match\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-match\",\"version\":\"7\",\"digest\":\"position-digest-match\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"liquidity\":\"9\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-other\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-other\",\"version\":\"8\",\"digest\":\"position-digest-other\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool3\",\"liquidity\":\"3\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-match\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-match\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-match\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-match\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize discovers shared candidates from event transaction object changes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xtx-pool\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"pool\",\"parsedJson\":{\"amount\":\"9\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0xtx-pool\",{\"showObjectChanges\":true}]"));
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"objectChanges\":[{\"type\":\"created\",\"objectId\":\"0xpool-from-tx\"}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool-from-tx\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool-from-tx\",\"version\":\"11\",\"digest\":\"pool-digest-tx\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "pool",
        "resolve_from_event_tx",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool-from-tx\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), shared_candidates.len);
    try testing.expectEqualStrings("0xpool-from-tx", shared_candidates[0].object.get("object_id").?.string);
}

test "runCommand move function with --summarize merges event parsedJson and transaction object changes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xtx-pool\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool-from-event\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0xtx-pool\",{\"showObjectChanges\":true}]"));
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"objectChanges\":[{\"type\":\"created\",\"objectId\":\"0xpool-from-tx\"}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool-from-event\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool-from-event\",\"version\":\"10\",\"digest\":\"pool-digest-event\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"6\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool-from-tx\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool-from-tx\",\"version\":\"11\",\"digest\":\"pool-digest-tx\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "pool",
        "resolve_from_event_merge",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), shared_candidates.len);
    try testing.expectEqualStrings("0xpool-from-event", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings("0xpool-from-tx", shared_candidates[1].object.get("object_id").?.string);
}

test "runCommand move function with --summarize prefers shared candidate with highest owned reference score" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-c\",\"version\":\"9\",\"digest\":\"position-digest-c\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"liquidity\":\"9\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"liquidity\":\"3\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-c\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-c\",\"version\":\"9\",\"digest\":\"position-digest-c\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\",\"liquidity\":\"5\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(i64, 2), shared_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 1), shared_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xpool2", shared_candidates[1].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-a\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-a\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[1].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize prefers owned candidate with highest selected object reference score" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"vault\",\"name\":\"Vault\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-c\",\"version\":\"9\",\"digest\":\"position-digest-c\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"vault_id\":\"0xvault1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-c\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-c\",\"version\":\"9\",\"digest\":\"position-digest-c\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"vault_id\":\"0xvault1\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--arg-at",
        "2",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xvault1\",\"inputKind\":\"shared\",\"initialSharedVersion\":5,\"mutable\":false}",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    const owned_candidates = parameters[1].object.get("owned_object_candidates").?.array.items;
    try testing.expect(owned_candidates[0].object.get("selection_score").?.integer >
        owned_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xposition-b", owned_candidates[0].object.get("object_id").?.string);
    try testing.expect(owned_candidates[1].object.get("selection_score").?.integer > 0);
    try testing.expect(owned_candidates[2].object.get("selection_score").?.integer > 0);
    const second_id = owned_candidates[1].object.get("object_id").?.string;
    const third_id = owned_candidates[2].object.get("object_id").?.string;
    try testing.expect(
        (std.mem.eql(u8, second_id, "0xposition-a") and std.mem.eql(u8, third_id, "0xposition-c")) or
            (std.mem.eql(u8, second_id, "0xposition-c") and std.mem.eql(u8, third_id, "0xposition-a")),
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xvault1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":5,\\\"mutable\\\":false}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize tie-breaks shared candidates by discovery order" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}},{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool2\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":8,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(i64, 7), shared_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqual(@as(i64, 7), shared_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xpool2", shared_candidates[0].object.get("object_id").?.string);
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize tie-breaks zero-score shared event candidates by discovery order" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}},{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "swap",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const shared_candidates = parameter.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(i64, 0), shared_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqual(@as(i64, 0), shared_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xpool2", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool2\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":8,\\\"mutable\\\":true}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize tie-breaks owned candidates by discovery order" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "0",
        "0xpool1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    const owned_candidates = parameters[1].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(i64, 14), owned_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqual(@as(i64, 14), owned_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xposition-b", owned_candidates[0].object.get("object_id").?.string);
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[1].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize tie-breaks zero-score owned candidates by discovery order" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"4\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::position::Position\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2a",
        .move_module = "router",
        .move_function = "deposit_position",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(i64, 0), owned_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqual(@as(i64, 0), owned_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xposition-b", owned_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize links shared object candidates to selected owned objects" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-match\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition-match\",\"version\":\"7\",\"digest\":\"position-digest-match\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"liquidity\":\"9\"}}}}}",
                        );
                    }
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-match\",\"version\":\"7\",\"digest\":\"position-digest-match\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--object-arg-at",
        "1",
        "0xposition-match",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), shared_candidates.len);
    try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-match\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-match\\\"}\"",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-match\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-match\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize merges shared candidates from events and owned content" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[],[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"objectChanges\":[]}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\",\"liquidity\":\"9\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "add_liquidity_fix_coin",
        "--type-arg",
        "0x2::sui::SUI",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), shared_candidates.len);
    try testing.expectEqualStrings("0xpool2", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings("0xpool1", shared_candidates[1].object.get("object_id").?.string);
    try testing.expect(shared_candidates[0].object.get("selection_score").?.integer > shared_candidates[1].object.get("selection_score").?.integer);
}

test "runCommand move function with --summarize caches shared event discovery across identical shared params" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct {
        query_events_requests: usize = 0,
        shared_summary_requests: usize = 0,
    };
    var state = State{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const callback_state = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                callback_state.query_events_requests += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"router\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null and
                std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null and
                std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null)
            {
                callback_state.shared_summary_requests += 1;
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "rebalance_twice",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    for (parameters[0..2]) |parameter| {
        const shared_candidates = parameter.object.get("shared_object_candidates").?.array.items;
        try testing.expectEqual(@as(usize, 1), shared_candidates.len);
        try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
        try testing.expectEqualStrings(
            "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
            parameter.object.get("auto_selected_arg_json").?.string,
        );
    }
    try testing.expectEqual(@as(usize, 1), state.query_events_requests);
    try testing.expectEqual(@as(usize, 1), state.shared_summary_requests);
}

test "runCommand move function with --summarize discovers related shared candidates from existing shared candidates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"config\",\"name\":\"Registry\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"router\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"registry_id\":\"0xregistry1\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"type\":\"0x2a::config::Registry<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "rebalance",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    const registry_candidates = parameters[1].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), registry_candidates.len);
    try testing.expectEqualStrings("0xregistry1", registry_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xregistry1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":9,\\\"mutable\\\":false}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize merges shared candidates from content and dynamic fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"config\",\"name\":\"Registry\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xpool-owner-2\"},\"type\":\"DynamicField\",\"objectType\":\"0x2a::pool::Pool\",\"objectId\":\"0xpool2\",\"version\":\"5\",\"digest\":\"pool-digest-2\"}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"type\":\"0x2a::config::Registry\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "rebalance",
        "--object-arg-at",
        "1",
        "0xregistry1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const pool_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), pool_candidates.len);
    try testing.expectEqualStrings("0xpool1", pool_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings("0xpool2", pool_candidates[1].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize caches repeated selected-object content discovery" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct {
        registry_content_requests: usize = 0,
    };
    var state = State{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const callback_state = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"config\",\"name\":\"Registry\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xpool-owner-2\"},\"type\":\"DynamicField\",\"objectType\":\"0x2a::pool::Pool\",\"objectId\":\"0xpool2\",\"version\":\"5\",\"digest\":\"pool-digest-2\"}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    callback_state.registry_content_requests += 1;
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"type\":\"0x2a::config::Registry\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "rebalance",
        "--object-arg-at",
        "1",
        "0xregistry1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const pool_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), pool_candidates.len);
    try testing.expectEqual(@as(usize, 1), state.registry_content_requests);
}

test "runCommand move function with --summarize discovers shared candidates from dynamic fields of selected objects" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct {
        registry_dynamic_field_requests: usize = 0,
    };
    var state = State{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const callback_state = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"config\",\"name\":\"Registry\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                    callback_state.registry_dynamic_field_requests += 1;
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xpool-owner\"},\"type\":\"DynamicField\",\"objectType\":\"0x2a::pool::Pool\",\"objectId\":\"0xpool1\",\"version\":\"4\",\"digest\":\"pool-digest-1\"}],\"hasNextPage\":false}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"name\":\"registry\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"type\":\"0x2a::config::Registry\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "rebalance",
        "--object-arg-at",
        "1",
        "0xregistry1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const pool_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), pool_candidates.len);
    try testing.expectEqualStrings("0xpool1", pool_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xregistry1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":9,\\\"mutable\\\":false}\"",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqual(@as(usize, 1), state.registry_dynamic_field_requests);
}

test "runCommand move function with --summarize discovers owned candidates from discovered object content" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2a\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                if (std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::position::Position\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::receipt::Receipt\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"7\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"7\",\"digest\":\"receipt-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition1\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"7\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "redeem",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const position_candidates = parameters[0].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), position_candidates.len);
    try testing.expectEqualStrings("0xposition1", position_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"receipt-digest-1\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize discovers owned candidates from dynamic fields of selected objects" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"config\",\"name\":\"Registry\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xposition-owner\"},\"type\":\"DynamicField\",\"objectType\":\"0x2a::position::Position\",\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\"}],\"hasNextPage\":false}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"name\":\"registry\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"type\":\"0x2a::config::Registry\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
            if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                );
            }
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "redeem",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "1",
        "0xregistry1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const position_candidates = parameters[0].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), position_candidates.len);
    try testing.expectEqualStrings("0xposition1", position_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xregistry1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":9,\\\"mutable\\\":false}\"",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
}

test "runCommand move function with --summarize merges owned candidates from content and dynamic fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"config\",\"name\":\"Registry\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xposition-owner-2\"},\"type\":\"DynamicField\",\"objectType\":\"0x2a::position::Position\",\"objectId\":\"0xposition2\",\"version\":\"12\",\"digest\":\"position-digest-2\"}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xregistry1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition1\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xregistry1\",\"version\":\"12\",\"digest\":\"registry-digest-1\",\"type\":\"0x2a::config::Registry\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"9\"}}}}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null);
            if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"12\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"4\"}}}}}",
                );
            }
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"12\",\"digest\":\"position-digest-2\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "redeem",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "1",
        "0xregistry1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    const position_candidates = parameters[0].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), position_candidates.len);
    try testing.expectEqualStrings("0xposition1", position_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings("0xposition2", position_candidates[1].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize discovers owned candidates from module events" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"router\",\"parsedJson\":{\"position_id\":\"0xposition1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }
            std.debug.panic("unexpected method {s}", .{req.method});
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "redeem",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), owned_candidates.len);
    try testing.expectEqualStrings("0xposition1", owned_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize falls back to owned event discovery from struct module" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct {
        router_event_requests: usize = 0,
        position_event_requests: usize = 0,
    };
    var state = State{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const callback_state = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getDynamicFields")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                if (std.mem.indexOf(u8, req.params_json, "\"module\":\"router\"") != null) {
                    callback_state.router_event_requests += 1;
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"module\":\"position\"") != null);
                callback_state.position_event_requests += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"position\",\"parsedJson\":{\"position_id\":\"0xposition1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null);
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"11\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }
            std.debug.panic("unexpected method {s}", .{req.method});
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "redeem",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), owned_candidates.len);
    try testing.expectEqualStrings("0xposition1", owned_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqual(@as(usize, 1), state.router_event_requests);
    try testing.expectEqual(@as(usize, 1), state.position_event_requests);
}

test "runCommand move function with --summarize avoids reusing generic owned objects across scalar params" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"4\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::position::Position\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2a",
        .move_module = "router",
        .move_function = "deposit_two_positions",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-a\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );

    const preferred_args = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
        .{},
    );
    defer preferred_args.deinit();
    try testing.expectEqual(@as(usize, 2), preferred_args.value.array.items.len);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xposition-a\",\"inputKind\":\"imm_or_owned\",\"version\":7,\"digest\":\"position-digest-a\"}",
        preferred_args.value.array.items[0].string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xposition-b\",\"inputKind\":\"imm_or_owned\",\"version\":8,\"digest\":\"position-digest-b\"}",
        preferred_args.value.array.items[1].string,
    );
}

test "runCommand move function with --summarize reserves later explicit owned objects before auto-selection" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null);
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"4\"}}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::position::Position\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "router",
        "deposit_two_positions",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "1",
        "0xposition-a",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-a\\\"}\"",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
}

test "runCommand move function with --summarize avoids reusing scalar owned objects in later vector object params" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}},{\"Vector\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"9\"}}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xposition-b\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"liquidity\":\"4\"}}}}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2a::position::Position\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition-b\",\"version\":\"8\",\"digest\":\"position-digest-b\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2a",
        .move_module = "router",
        .move_function = "deposit_position_and_many",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-a\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-b\\\"}\"]",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );

    const preferred_args = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
        .{},
    );
    defer preferred_args.deinit();
    try testing.expectEqual(@as(usize, 2), preferred_args.value.array.items.len);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xposition-a\",\"inputKind\":\"imm_or_owned\",\"version\":7,\"digest\":\"position-digest-a\"}",
        preferred_args.value.array.items[0].string,
    );
    try testing.expectEqual(@as(usize, 1), preferred_args.value.array.items[1].array.items.len);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xposition-b\",\"inputKind\":\"imm_or_owned\",\"version\":8,\"digest\":\"position-digest-b\"}",
        preferred_args.value.array.items[1].array.items[0].string,
    );
}

test "runCommand move function with --summarize iterates joint candidate selection to a fixed point" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"vault\",\"name\":\"Vault\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"router\",\"name\":\"Router\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\",\"router_id\":\"0xrouter1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x2a\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\",\"router_id\":\"0xrouter2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0x2a::position::Position\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0x2a::receipt::Receipt\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"4\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"5\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xrouter1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xrouter1\",\"version\":\"13\",\"digest\":\"router-digest-1\",\"type\":\"0x2a::router::Router<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"6\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xrouter2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xrouter2\",\"version\":\"14\",\"digest\":\"router-digest-2\",\"type\":\"0x2a::router::Router<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xvault1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xvault1\",\"version\":\"15\",\"digest\":\"vault-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"note\":\"vault\"}}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xvault1\",\"version\":\"15\",\"digest\":\"vault-digest-1\",\"type\":\"0x2a::vault::Vault\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"vault_id\":\"0xvault1\",\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition1\",\"router_id\":\"0xrouter1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition2\",\"router_id\":\"0xrouter2\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "pool",
        "deep_link",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "3",
        "0xvault1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":4,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"receipt-digest-1\\\"}\"",
        parameters[2].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xrouter1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":6,\\\"mutable\\\":false}\"",
        parameters[4].object.get("auto_selected_arg_json").?.string,
    );
    const router_candidates = parameters[4].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xrouter1", router_candidates[0].object.get("object_id").?.string);
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[4].object.get("resolution_kind").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":4,\\\"mutable\\\":true}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-1\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"receipt-digest-1\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xvault1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":8,\\\"mutable\\\":false}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xrouter1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":6,\\\"mutable\\\":false}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize prefers the larger connected candidate cluster" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2a\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2a\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x2a\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0x2a::position::Position\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0x2a::receipt::Receipt\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xreceipt2a\",\"version\":\"9\",\"digest\":\"receipt-digest-2a\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xreceipt2b\",\"version\":\"10\",\"digest\":\"receipt-digest-2b\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"4\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2a::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"5\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2a::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt2a\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2a\",\"version\":\"9\",\"digest\":\"receipt-digest-2a\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2a\",\"version\":\"9\",\"digest\":\"receipt-digest-2a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition2\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt2b\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2b\",\"version\":\"10\",\"digest\":\"receipt-digest-2b\",\"type\":\"0x2a::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2b\",\"version\":\"10\",\"digest\":\"receipt-digest-2b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition2\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2a",
        "pool",
        "cluster_pick",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool2\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":5,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition2\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-2\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt2a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"receipt-digest-2a\\\"}\"",
        parameters[2].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xpool2", shared_candidates[0].object.get("object_id").?.string);
    try testing.expect(shared_candidates[0].object.get("selection_score").?.integer > shared_candidates[1].object.get("selection_score").?.integer);
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[1].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize prefers candidate clusters anchored by explicit objects" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2b\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2b\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2b\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2b\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x2b\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0x2b::position::Position\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2b::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2b::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2b::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"5\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2b::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"6\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2b::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2b::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt-explicit\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-explicit\",\"version\":\"9\",\"digest\":\"receipt-digest-explicit\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"position_id\":\"0xposition2\"}}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-explicit\",\"version\":\"9\",\"digest\":\"receipt-digest-explicit\",\"type\":\"0x2b::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2b",
        "pool",
        "anchored_cluster",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "2",
        "0xreceipt-explicit",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool2\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":6,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition2\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"position-digest-2\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xpool2", shared_candidates[0].object.get("object_id").?.string);
    try testing.expect(shared_candidates[0].object.get("selection_score").?.integer > shared_candidates[1].object.get("selection_score").?.integer);
    const owned_candidates = parameters[1].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xposition2", owned_candidates[0].object.get("object_id").?.string);
    try testing.expect(owned_candidates[0].object.get("selection_score").?.integer > owned_candidates[1].object.get("selection_score").?.integer);
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[1].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize prefers internally consistent candidate clusters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2c\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"TypeParameter\":0}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2c\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2c\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2c\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x2c\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0x2c::position::Position\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2c::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2c::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0x2c::receipt::Receipt\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2c::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"type\":\"0x2c::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2c::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"5\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2c::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"6\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2c::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2c::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2c::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"position_id\":\"0xposition1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"type\":\"0x2c::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
                "move",
                "function",
                "0x2c",
                "pool",
                "consistent_cluster",
                "--type-arg",
                "0x2::sui::SUI",
                "--sender",
                "0xowner",
                "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":5,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"receipt-digest-1\\\"}\"",
        parameters[2].object.get("auto_selected_arg_json").?.string,
    );

    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
    try testing.expect(shared_candidates[0].object.get("selection_score").?.integer > shared_candidates[1].object.get("selection_score").?.integer);
    const owned_candidates = parameters[1].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xposition1", owned_candidates[0].object.get("object_id").?.string);
    try testing.expect(owned_candidates[0].object.get("selection_score").?.integer > owned_candidates[1].object.get("selection_score").?.integer);
    const receipt_candidates = parameters[2].object.get("owned_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xreceipt1", receipt_candidates[0].object.get("object_id").?.string);
    try testing.expect(receipt_candidates[0].object.get("selection_score").?.integer > receipt_candidates[1].object.get("selection_score").?.integer);
}

test "runCommand move function with --summarize deterministically tie-breaks equally consistent candidate clusters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2d\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"TypeParameter\":0}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2d\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2d\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2d\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x2d\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0x2d::position::Position\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2d::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2d::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0x2d::receipt::Receipt\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2d::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"type\":\"0x2d::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2d::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"5\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x2d::pool::Pool<0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"6\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"type\":\"0x2d::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition1\",\"version\":\"7\",\"digest\":\"position-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"type\":\"0x2d::position::Position\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition2\",\"version\":\"8\",\"digest\":\"position-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt1\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"type\":\"0x2d::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt1\",\"version\":\"9\",\"digest\":\"receipt-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt2\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") == null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"type\":\"0x2d::receipt::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt2\",\"version\":\"10\",\"digest\":\"receipt-digest-2\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2d",
        "pool",
        "deterministic_cluster",
        "--type-arg",
        "0x2::sui::SUI",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":5,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xposition1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"position-digest-1\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"receipt-digest-1\\\"}\"",
        parameters[2].object.get("auto_selected_arg_json").?.string,
    );
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expectEqualStrings(
        "auto_selected_tiebreak",
        preferred_resolution.get("parameters").?.array.items[1].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --summarize carries sender and signer context into call templates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0x2\",\"pool\",\"swap\"]"));
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--sender",
        "0xowner",
        "--signer",
        "builder",
        "--from-keystore",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const template = parsed.value.object.get("call_template").?.object;
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}],\"sender\":\"0xowner\",\"gasBudget\":100000000,\"gasPrice\":1000,\"autoGasPayment\":true,\"autoGasBudget\":true,\"summarize\":true}",
        template.get("tx_dry_run_request_json").?.string,
    );
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}],\"fromKeystore\":true,\"signer\":\"builder\",\"gasBudget\":100000000,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}",
        template.get("tx_send_from_keystore_request_json").?.string,
    );
    const preferred_resolution = template.get("preferred_resolution").?.object;
    try testing.expect(!preferred_resolution.get("is_fully_resolved").?.bool);
    const unresolved = preferred_resolution.get("unresolved_parameter_indices").?.array.items;
    try testing.expectEqual(@as(usize, 1), unresolved.len);
    try testing.expectEqual(@as(i64, 0), unresolved[0].integer);
    const resolution_parameters = preferred_resolution.get("parameters").?.array.items;
    try testing.expectEqualStrings("placeholder", resolution_parameters[0].object.get("resolution_kind").?.string);
    try testing.expect(!resolution_parameters[0].object.get("is_executable").?.bool);
    try testing.expectEqualStrings(
        "\"<arg0-object-id-or-select-token>\"",
        resolution_parameters[0].object.get("resolved_arg_json").?.string,
    );
    try testing.expectEqualStrings("placeholder", resolution_parameters[1].object.get("resolution_kind").?.string);
    try testing.expect(resolution_parameters[1].object.get("is_executable").?.bool);
    try testing.expectEqualStrings("0", resolution_parameters[1].object.get("resolved_arg_json").?.string);
    try testing.expectEqualStrings("runtime_omitted", resolution_parameters[2].object.get("resolution_kind").?.string);
    try testing.expect(resolution_parameters[2].object.get("is_executable").?.bool);
    try testing.expectEqual(std.json.Value.null, resolution_parameters[2].object.get("resolved_arg_json").?);
    const dry_run_argv = template.get("tx_dry_run_argv").?.array.items;
    try testing.expectEqualStrings("--sender", dry_run_argv[12].string);
    try testing.expectEqualStrings("0xowner", dry_run_argv[13].string);
    const send_argv = template.get("tx_send_from_keystore_argv").?.array.items;
    try testing.expectEqualStrings("--signer", send_argv[13].string);
    try testing.expectEqualStrings("builder", send_argv[14].string);
}

test "runCommand move function with --summarize falls back to sender address for keystore signer template" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0x2\",\"pool\",\"swap\"]"));
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--sender",
        "0xowner",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const template = parsed.value.object.get("call_template").?.object;
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}],\"fromKeystore\":true,\"signer\":\"0xowner\",\"gasBudget\":100000000,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}",
        template.get("tx_send_from_keystore_request_json").?.string,
    );
    const send_argv = template.get("tx_send_from_keystore_argv").?.array.items;
    try testing.expectEqualStrings("0xowner", send_argv[14].string);
}

test "runCommand move function with --summarize auto-selects address and signer parameters from owner context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0x2\",\"auth\",\"authorize\"]"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[\"address\",\"signer\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "auth",
        "authorize",
        "--sender",
        "0xowner",
        "--signer",
        "builder",
        "--from-keystore",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings("\"0xowner\"", parameters[0].object.get("auto_selected_arg_json").?.string);
    try testing.expectEqualStrings("\"0xowner\"", parameters[1].object.get("auto_selected_arg_json").?.string);
    const template = parsed.value.object.get("call_template").?.object;
    try testing.expectEqualStrings("[\"0xowner\",\"0xowner\"]", template.get("preferred_args_json").?.string);
    const preferred_resolution = template.get("preferred_resolution").?.object;
    try testing.expect(preferred_resolution.get("is_fully_resolved").?.bool);
    try testing.expectEqual(@as(usize, 0), preferred_resolution.get("unresolved_parameter_indices").?.array.items.len);
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[1].object.get("resolution_kind").?.string,
    );
    const preferred_request = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_tx_send_from_keystore_request_json").?.string,
        .{},
    );
    defer preferred_request.deinit();
    try testing.expectEqualStrings("builder", preferred_request.value.object.get("signer").?.string);
    const preferred_commands = preferred_request.value.object.get("commands").?.array.items;
    const preferred_arguments = preferred_commands[0].object.get("arguments").?.array.items;
    try testing.expectEqualStrings("0xowner", preferred_arguments[0].string);
    try testing.expectEqualStrings("0xowner", preferred_arguments[1].string);
}

test "runCommand move function with --emit-template prints preferred dry-run request output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }

            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "swap",
        "--emit-template",
        "preferred-dry-run-request",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("0x<sender>", parsed.value.object.get("sender").?.string);
    try testing.expect(parsed.value.object.get("autoGasPayment").?.bool);
    try testing.expect(parsed.value.object.get("autoGasBudget").?.bool);
    const resolution = parsed.value.object.get("preferredResolution").?.object;
    try testing.expect(resolution.get("is_fully_resolved").?.bool);
    try testing.expectEqual(@as(usize, 0), resolution.get("unresolved_parameter_indices").?.array.items.len);
    try testing.expectEqualStrings(
        "auto_selected",
        resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
}

test "runCommand move function with --dry-run executes preferred dry-run request artifact" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"7\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinObjectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"balance\":\"1000000000\"}],\"nextCursor\":null,\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "counter",
        "increment",
        "--sender",
        "0x1111111111111111111111111111111111111111111111111111111111111111",
        "--arg",
        "7",
        "--dry-run",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 3), counts.normalized);
    try testing.expectEqual(@as(usize, 2), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);

    try testing.expect(std.mem.indexOf(u8, output.items, "success") != null);
}

test "runCommand move function with --dry-run auto-resolves address and signer parameters from owner context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[\"address\",\"signer\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"7\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinObjectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"balance\":\"1000000000\"}],\"nextCursor\":null,\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "auth",
        "authorize",
        "--sender",
        "0x1111111111111111111111111111111111111111111111111111111111111111",
        "--dry-run",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(counts.normalized >= 1);
    try testing.expectEqual(@as(usize, 2), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(std.mem.indexOf(u8, output.items, "success") != null);
}

test "runCommand move function with --send executes preferred send request artifact" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x52} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);

    const keystore_path = "tmp_move_function_send_keystore.json";
    try std.fs.cwd().writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer std.fs.cwd().deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    const State = struct {
        gas_price: usize = 0,
        normalized: usize = 0,
        dry_run: usize = 0,
        execute_calls: usize = 0,
        unsafe_calls: usize = 0,
    };
    var state = State{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                ctx.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"9\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinObjectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"balance\":\"1000000000\"}],\"nextCursor\":null,\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_calls += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"digest\":\"0xmovefunctionsend\",\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"digest\":\"0xmovefunctionsend\",\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe_calls += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "counter",
        "increment",
        "--from-keystore",
        "--signer",
        "0",
        "--arg",
        "7",
        "--send",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 3), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.dry_run);
    try testing.expectEqual(@as(usize, 1), state.execute_calls);
    try testing.expectEqual(@as(usize, 0), state.unsafe_calls);

    try testing.expect(std.mem.indexOf(u8, output.items, "success") != null);
}

test "runCommand move function indexed explicit args override parameter positions in preferred templates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--arg",
        "7",
        "--arg-at",
        "0",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xpool1\",\"inputKind\":\"shared\",\"initialSharedVersion\":7,\"mutable\":true}",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "7",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",7]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function indexed object args resolve exact object input tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x2::pool::Pool\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--arg",
        "7",
        "--object-arg-at",
        "0",
        "0xpool1",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "7",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\",7]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function indexed vector object args resolve exact object input tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            if (std.mem.indexOf(u8, req.params_json, "\"0xcoin1\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xcoin1\",\"version\":\"9\",\"digest\":\"coin-digest-1\",\"type\":\"0x2::coin::Coin<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }

            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xcoin2\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xcoin2\",\"version\":\"10\",\"digest\":\"coin-digest-2\",\"type\":\"0x2::coin::Coin<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "router",
        "deposit_many",
        "--object-arg-at",
        "0",
        "[\"0xcoin1\",\"0xcoin2\"]",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-1\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin2\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-2\\\"}\"]",
        parameter.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-1\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin2\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-2\\\"}\"]]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "selectExecutableMoveFunctionRequestArtifact falls back to executable base request" {
    const testing = std.testing;

    const allocator = testing.allocator;
    const selection = try selectExecutableMoveFunctionRequestArtifact(
        allocator,
        "{\"commands\":[{\"kind\":\"MoveCall\",\"arguments\":[\"<arg0-object-id-or-select-token>\"]}],\"preferredResolution\":{\"unresolved_parameter_indices\":[0]}}",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"arguments\":[7]}]}",
    );

    try testing.expect(!selection.used_preferred);
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"arguments\":[7]}]}",
        selection.request_json,
    );
}

test "selectExecutableMoveFunctionRequestArtifact keeps executable preferred request" {
    const testing = std.testing;

    const allocator = testing.allocator;
    const selection = try selectExecutableMoveFunctionRequestArtifact(
        allocator,
        "{\"commands\":[{\"kind\":\"MoveCall\",\"arguments\":[13]}],\"preferredResolution\":{\"unresolved_parameter_indices\":[]}}",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"arguments\":[7]}]}",
    );

    try testing.expect(selection.used_preferred);
    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"arguments\":[13]}],\"preferredResolution\":{\"unresolved_parameter_indices\":[]}}",
        selection.request_json,
    );
}

test "runCommand move function with direct execution rejects unresolved template placeholders" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--dry-run",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(
        error.UnresolvedMoveFunctionExecutionTemplate,
        runCommand(allocator, &rpc, &args, output.writer(allocator)),
    );
}

test "runCommand move function with --summarize uses queried package for shared object event discovery and candidates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                std.debug.assert(std.mem.eql(
                    u8,
                    req.params_json,
                    "[{\"MoveModule\":{\"package\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"module\":\"pool\"}},null,20,true]",
                ));
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\",\"partner_id\":\"0xpartner\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }

            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"note\":\"pool\"}}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpartner\",\"version\":\"12\",\"digest\":\"partner-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"note\":\"partner\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpartner\",\"version\":\"12\",\"digest\":\"partner-digest-1\",\"type\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3::partner::Partner\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"3\"}}}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "swap",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const shared_event_argv = parameter.get("shared_object_event_query_argv").?.array.items;
    try testing.expectEqual(@as(usize, 8), shared_event_argv.len);
    try testing.expectEqualStrings("events", shared_event_argv[0].string);
    try testing.expectEqualStrings("--package", shared_event_argv[1].string);
    try testing.expectEqualStrings(client.package_preset.cetus_clmm_mainnet, shared_event_argv[2].string);
    try testing.expectEqualStrings("--module", shared_event_argv[3].string);
    try testing.expectEqualStrings("pool", shared_event_argv[4].string);
    try testing.expectEqualStrings("20", shared_event_argv[6].string);
    const shared_candidates = parameter.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 1), shared_candidates.len);
    try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>",
        shared_candidates[0].object.get("type_name").?.string,
    );
    try testing.expectEqual(@as(i64, 7), shared_candidates[0].object.get("initial_shared_version").?.integer);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xpool1\",\"inputKind\":\"shared\",\"initialSharedVersion\":7,\"mutable\":false}",
        shared_candidates[0].object.get("shared_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xpool1\",\"inputKind\":\"shared\",\"initialSharedVersion\":7,\"mutable\":true}",
        shared_candidates[0].object.get("mutable_shared_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"]}]",
        parsed.value.object.get("call_template").?.object.get("preferred_commands_json").?.string,
    );
    const preferred_request = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        parsed.value.object.get("call_template").?.object.get("preferred_tx_dry_run_request_json").?.string,
        .{},
    );
    defer preferred_request.deinit();
    try testing.expectEqualStrings("0x<sender>", preferred_request.value.object.get("sender").?.string);
    const preferred_resolution = preferred_request.value.object.get("preferredResolution").?.object;
    try testing.expect(preferred_resolution.get("is_fully_resolved").?.bool);
    try testing.expectEqual(@as(usize, 0), preferred_resolution.get("unresolved_parameter_indices").?.array.items.len);
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expect(preferred_resolution.get("parameters").?.array.items[0].object.get("is_executable").?.bool);
}

test "runCommand move function with --summarize discovers shared object candidates across event pages" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_request_count: usize = 0;

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const request_count = @as(*usize, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":false,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                request_count.* += 1;
                if (request_count.* == 1) {
                    std.debug.assert(std.mem.eql(
                        u8,
                        req.params_json,
                        "[{\"MoveModule\":{\"package\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"module\":\"pool\"}},null,20,true]",
                    ));
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"partner_id\":\"0xpartner\"}}],\"nextCursor\":{\"txDigest\":\"0xcursor-next\",\"eventSeq\":\"2\"},\"hasNextPage\":true}}",
                    );
                }

                std.debug.assert(std.mem.eql(
                    u8,
                    req.params_json,
                    "[{\"MoveModule\":{\"package\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"module\":\"pool\"}},{\"txDigest\":\"0xcursor-next\",\"eventSeq\":\"2\"},20,true]",
                ));
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"3\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }

            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            if (std.mem.indexOf(u8, req.params_json, "\"0xpartner\"") != null) {
                if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpartner\",\"version\":\"12\",\"digest\":\"partner-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"note\":\"partner\"}}}}}",
                    );
                }
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpartner\",\"version\":\"12\",\"digest\":\"partner-digest-1\",\"type\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3::partner::Partner\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"3\"}}}}}",
                );
            }

            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null);
            if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"note\":\"pool\"}}}}}",
                );
            }
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .move_module = "pool",
        .move_function = "swap",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &event_request_count,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    const shared_candidates = parameter.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), event_request_count);
    try testing.expectEqual(@as(usize, 1), shared_candidates.len);
    try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --emit-template falls back to base send request output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0x2\",\"pool\",\"swap\"]"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "pool",
        "swap",
        "--emit-template",
        "preferred-send-request",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqualStrings(
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[\"<arg0-object-id-or-select-token>\",0]}],\"fromKeystore\":true,\"signer\":\"<alias-or-address>\",\"gasBudget\":100000000,\"autoGasPayment\":true,\"autoGasBudget\":true,\"wait\":true,\"summarize\":true}\n",
        output.items,
    );
}

test "runCommand move function with --summarize specializes generic signatures with type arguments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2\"") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"pool\"") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"swap_generic\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"TypeParameter\":0}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}}]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_queryEvents"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "pool",
        .move_function = "swap_generic",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings(
        "[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]",
        parsed.value.object.get("applied_type_args_json").?.string,
    );
    try testing.expectEqualStrings(
        "&mut 0x2::pool::Pool<0x2::sui::SUI>",
        parsed.value.object.get("parameters").?.array.items[0].object.get("signature").?.string,
    );
    try testing.expectEqualStrings(
        "0x2::coin::Coin<0x2::sui::SUI>",
        parsed.value.object.get("returns").?.array.items[0].object.get("signature").?.string,
    );
    try testing.expectEqual(
        std.json.Value.null,
        parsed.value.object.get("parameters").?.array.items[0].object.get("owned_object_select_token").?,
    );
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("parameters").?.array.items[0].object.get("auto_selected_arg_json").?);
    try testing.expectEqualStrings(
        "[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]",
        parsed.value.object.get("call_template").?.object.get("type_args_json").?.string,
    );
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("call_template").?.object.get("preferred_args_json").?);
}

test "runCommand move function with --summarize adds vector object discovery templates after type specialization" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"router\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"deposit_many\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_many",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "vector<0x2::coin::Coin<0x2::sui::SUI>>",
        parameter.get("signature").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":1}\"]",
        parameter.get("placeholder_json").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"coin_with_min_balance\",\"coinType\":\"0x2::sui::SUI\",\"minBalance\":1}",
        parameter.get("vector_item_coin_with_min_balance_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x<arg0-item0-object-id>\",\"inputKind\":\"imm_or_owned\"}",
        parameter.get("vector_item_imm_or_owned_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"structType\":\"0x2::coin::Coin<0x2::sui::SUI>\"}",
        parameter.get("vector_item_owned_object_select_token").?.string,
    );
    const vector_item_get_argv = parameter.get("vector_item_object_get_argv").?.array.items;
    try testing.expectEqual(@as(usize, 4), vector_item_get_argv.len);
    try testing.expectEqualStrings("object", vector_item_get_argv[0].string);
    try testing.expectEqualStrings("get", vector_item_get_argv[1].string);
    try testing.expectEqualStrings("0x<arg0-item0-object-id>", vector_item_get_argv[2].string);
    try testing.expectEqualStrings("--summarize", vector_item_get_argv[3].string);
    const vector_item_query_argv = parameter.get("vector_item_owned_object_query_argv").?.array.items;
    try testing.expectEqual(@as(usize, 6), vector_item_query_argv.len);
    try testing.expectEqualStrings("account", vector_item_query_argv[0].string);
    try testing.expectEqualStrings("coins", vector_item_query_argv[1].string);
    try testing.expectEqualStrings("0x<owner>", vector_item_query_argv[2].string);
    try testing.expectEqualStrings("--coin-type", vector_item_query_argv[3].string);
    try testing.expectEqualStrings("0x2::sui::SUI", vector_item_query_argv[4].string);
    try testing.expectEqualStrings(
        "[[\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":1}\"]]",
        parsed.value.object.get("call_template").?.object.get("args_json").?.string,
    );
    try testing.expectEqual(std.json.Value.null, parameter.get("auto_selected_arg_json").?);
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("call_template").?.object.get("preferred_args_json").?);
}

test "runCommand move function with --summarize fills owner context into vector object discovery templates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, ",20]") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin1\",\"version\":\"9\",\"digest\":\"coin-digest-1\",\"balance\":\"7\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin2\",\"version\":\"10\",\"digest\":\"coin-digest-2\",\"balance\":\"42\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_many",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":1}\"]",
        parameter.get("placeholder_json").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"coin_with_min_balance\",\"owner\":\"0xowner\",\"coinType\":\"0x2::sui::SUI\",\"minBalance\":1}",
        parameter.get("vector_item_coin_with_min_balance_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::coin::Coin<0x2::sui::SUI>\"}",
        parameter.get("vector_item_owned_object_select_token").?.string,
    );
    const vector_item_query_argv = parameter.get("vector_item_owned_object_query_argv").?.array.items;
    try testing.expectEqualStrings("coins", vector_item_query_argv[1].string);
    try testing.expectEqualStrings("0xowner", vector_item_query_argv[2].string);
    try testing.expectEqualStrings("--coin-type", vector_item_query_argv[3].string);
    try testing.expectEqualStrings("0x2::sui::SUI", vector_item_query_argv[4].string);
    const vector_item_candidates = parameter.get("vector_item_owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), vector_item_candidates.len);
    try testing.expectEqualStrings("0xcoin1", vector_item_candidates[0].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 9), vector_item_candidates[0].object.get("version").?.integer);
    try testing.expectEqualStrings("coin-digest-1", vector_item_candidates[0].object.get("digest").?.string);
    try testing.expectEqual(@as(i64, 7), vector_item_candidates[0].object.get("balance").?.integer);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin1\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"coin-digest-1\"}",
        vector_item_candidates[0].object.get("object_input_select_token").?.string,
    );
    try testing.expectEqualStrings("0xcoin2", vector_item_candidates[1].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 10), vector_item_candidates[1].object.get("version").?.integer);
    try testing.expectEqualStrings("coin-digest-2", vector_item_candidates[1].object.get("digest").?.string);
    try testing.expectEqual(@as(i64, 42), vector_item_candidates[1].object.get("balance").?.integer);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin2\",\"inputKind\":\"imm_or_owned\",\"version\":10,\"digest\":\"coin-digest-2\"}",
        vector_item_candidates[1].object.get("object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-1\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin2\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-2\\\"}\"]",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin1\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-1\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin2\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-2\\\"}\"]]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
    const preferred_request = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        parsed.value.object.get("call_template").?.object.get("preferred_tx_send_from_keystore_request_json").?.string,
        .{},
    );
    defer preferred_request.deinit();
    try testing.expect(preferred_request.value.object.get("fromKeystore").?.bool);
    try testing.expectEqualStrings("0xowner", preferred_request.value.object.get("signer").?.string);
    const preferred_resolution = preferred_request.value.object.get("preferredResolution").?.object;
    try testing.expect(preferred_resolution.get("is_fully_resolved").?.bool);
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expect(preferred_resolution.get("parameters").?.array.items[0].object.get("is_executable").?.bool);
}

test "runCommand move function with --summarize scores shared candidates from selected object references" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"position\",\"name\":\"Position\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"receipt\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb\",\"module\":\"ticket\",\"name\":\"Ticket\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool1\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"transactionModule\":\"pool\",\"parsedJson\":{\"pool_id\":\"0xpool2\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool1\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool1\",\"version\":\"11\",\"digest\":\"pool-digest-1\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpool2\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpool2\",\"version\":\"12\",\"digest\":\"pool-digest-2\",\"type\":\"0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xposition-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xposition-a\",\"version\":\"7\",\"digest\":\"position-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-a\",\"version\":\"8\",\"digest\":\"receipt-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xticket-b\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xticket-b\",\"version\":\"9\",\"digest\":\"ticket-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool2\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        client.package_preset.cetus_clmm_mainnet,
        "pool",
        "resolve_pool",
        "--arg-at",
        "1",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xposition-a\",\"inputKind\":\"imm_or_owned\",\"version\":7,\"digest\":\"position-digest-a\"}",
        "--arg-at",
        "2",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xreceipt-a\",\"inputKind\":\"imm_or_owned\",\"version\":8,\"digest\":\"receipt-digest-a\"}",
        "--arg-at",
        "3",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xticket-b\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"ticket-digest-b\"}",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpool1\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":7,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), shared_candidates.len);
    try testing.expectEqualStrings("0xpool1", shared_candidates[0].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 6), shared_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xpool2", shared_candidates[1].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 3), shared_candidates[1].object.get("selection_score").?.integer);
    const preferred_resolution = parsed.value.object.get("call_template").?.object.get("preferred_resolution").?.object;
    try testing.expectEqualStrings(
        "auto_selected",
        preferred_resolution.get("parameters").?.array.items[0].object.get("resolution_kind").?.string,
    );
    try testing.expect(preferred_resolution.get("parameters").?.array.items[0].object.get("is_executable").?.bool);
}

test "runCommand move function with --summarize weights explicit object references above auto-selected ones for shared candidates" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Pool\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Ticket\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_queryEvents")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"id\":{\"txDigest\":\"0xevent1\",\"eventSeq\":\"1\"},\"packageId\":\"0x2\",\"transactionModule\":\"example\",\"parsedJson\":{\"pool_id\":\"0xpoola\"}},{\"id\":{\"txDigest\":\"0xevent2\",\"eventSeq\":\"2\"},\"packageId\":\"0x2\",\"transactionModule\":\"example\",\"parsedJson\":{\"pool_id\":\"0xpoolb\"}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                return alloc.dupe(u8, "{\"result\":{\"objectChanges\":[]}}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                if (std.mem.indexOf(u8, req.params_json, "\"0x2::example::Ticket\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xticket-auto\",\"version\":\"9\",\"digest\":\"ticket-digest-auto\",\"type\":\"0x2::example::Ticket\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0x2::example::Receipt\"") != null) {
                    return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
                }
                return alloc.dupe(u8, "{\"result\":{\"data\":[],\"hasNextPage\":false}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xpoola\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpoola\",\"version\":\"11\",\"digest\":\"pool-digest-a\",\"type\":\"0x2::example::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xpoolb\"") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xpoolb\",\"version\":\"12\",\"digest\":\"pool-digest-b\",\"type\":\"0x2::example::Pool<0x2::sui::SUI, 0x2::sui::SUI>\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"8\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt-explicit\"") != null) {
                    if (std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null) {
                        return alloc.dupe(
                            u8,
                            "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-explicit\",\"version\":\"7\",\"digest\":\"receipt-digest-explicit\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpoolb\"}}}}}",
                        );
                    }
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-explicit\",\"version\":\"7\",\"digest\":\"receipt-digest-explicit\",\"type\":\"0x2::example::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xticket-auto\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xticket-auto\",\"version\":\"9\",\"digest\":\"ticket-digest-auto\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpoola\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "example",
        "select_pool",
        "--sender",
        "0xowner",
        "--object-arg-at",
        "1",
        "0xreceipt-explicit",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xpoolb\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":8,\\\"mutable\\\":true}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    const shared_candidates = parameters[0].object.get("shared_object_candidates").?.array.items;
    try testing.expectEqualStrings("0xpoolb", shared_candidates[0].object.get("object_id").?.string);
    try testing.expect(shared_candidates[0].object.get("selection_score").?.integer > shared_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xpoola", shared_candidates[1].object.get("object_id").?.string);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xticket-auto\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"ticket-digest-auto\\\"}\"",
        parameters[2].object.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize ranks vector owned candidates from selected object references" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"pool\",\"name\":\"Pool\",\"typeParams\":[]}}},{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Receipt\",\"typeParams\":[]}}},{\"Reference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"vault\",\"name\":\"Vault\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xreceipt-a\",\"version\":\"7\",\"digest\":\"receipt-digest-a\",\"type\":\"0x2::example::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xreceipt-b\",\"version\":\"8\",\"digest\":\"receipt-digest-b\",\"type\":\"0x2::example::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}},{\"data\":{\"objectId\":\"0xreceipt-c\",\"version\":\"9\",\"digest\":\"receipt-digest-c\",\"type\":\"0x2::example::Receipt\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt-a\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-a\",\"version\":\"7\",\"digest\":\"receipt-digest-a\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt-b\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-b\",\"version\":\"8\",\"digest\":\"receipt-digest-b\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"pool_id\":\"0xpool1\",\"vault_id\":\"0xvault1\"}}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "\"0xreceipt-c\"") != null) {
                    std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showContent\":true") != null);
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xreceipt-c\",\"version\":\"9\",\"digest\":\"receipt-digest-c\",\"content\":{\"dataType\":\"moveObject\",\"fields\":{\"vault_id\":\"0xvault1\"}}}}}",
                    );
                }
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "router",
        "settle_many",
        "--sender",
        "0xowner",
        "--arg-at",
        "0",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xpool1\",\"inputKind\":\"shared\",\"initialSharedVersion\":7,\"mutable\":true}",
        "--arg-at",
        "2",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xvault1\",\"inputKind\":\"imm_or_owned\",\"version\":5,\"digest\":\"vault-digest-1\"}",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[1].object;
    const vector_item_candidates = parameter.get("vector_item_owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 3), vector_item_candidates.len);
    try testing.expectEqualStrings("0xreceipt-b", vector_item_candidates[0].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 8), vector_item_candidates[0].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xreceipt-a", vector_item_candidates[1].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 4), vector_item_candidates[1].object.get("selection_score").?.integer);
    try testing.expectEqualStrings("0xreceipt-c", vector_item_candidates[2].object.get("object_id").?.string);
    try testing.expectEqual(@as(i64, 4), vector_item_candidates[2].object.get("selection_score").?.integer);
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt-b\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":8,\\\"digest\\\":\\\"receipt-digest-b\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt-a\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":7,\\\"digest\\\":\\\"receipt-digest-a\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xreceipt-c\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"receipt-digest-c\\\"}\"]",
        parameter.get("auto_selected_arg_json").?.string,
    );
}

test "runCommand move function with --summarize chooses covering vector coin candidates from explicit amount" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-small\",\"version\":\"9\",\"digest\":\"coin-digest-small\",\"balance\":\"2\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-mid\",\"version\":\"10\",\"digest\":\"coin-digest-mid\",\"balance\":\"5\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"11\",\"digest\":\"coin-digest-large\",\"balance\":\"9\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_many_exact",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[11]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"coin-digest-large\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\"]",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"coin-digest-large\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\"],11]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize prefers largest scalar coin candidate" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, ",20]") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-small\",\"version\":\"9\",\"digest\":\"coin-digest-small\",\"balance\":\"7\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"10\",\"digest\":\"coin-digest-large\",\"balance\":\"42\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_one",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "select:{\"kind\":\"coin_with_min_balance\",\"owner\":\"0xowner\",\"coinType\":\"0x2::sui::SUI\",\"minBalance\":1}",
        parameter.get("coin_with_min_balance_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":1}\"",
        parameter.get("placeholder_json").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::coin::Coin<0x2::sui::SUI>\"}",
        parameter.get("owned_object_select_token").?.string,
    );
    const owned_query_argv = parameter.get("owned_object_query_argv").?.array.items;
    try testing.expectEqualStrings("coins", owned_query_argv[1].string);
    try testing.expectEqualStrings("--coin-type", owned_query_argv[3].string);
    try testing.expectEqualStrings("0x2::sui::SUI", owned_query_argv[4].string);
    const owned_candidates = parameter.get("owned_object_candidates").?.array.items;
    try testing.expectEqual(@as(usize, 2), owned_candidates.len);
    try testing.expectEqual(@as(i64, 7), owned_candidates[0].object.get("balance").?.integer);
    try testing.expectEqual(@as(i64, 42), owned_candidates[1].object.get("balance").?.integer);
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-large\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-large\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize chooses smallest sufficient scalar coin candidate from explicit amount" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-small\",\"version\":\"9\",\"digest\":\"coin-digest-small\",\"balance\":\"7\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-fit\",\"version\":\"10\",\"digest\":\"coin-digest-fit\",\"balance\":\"13\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"11\",\"digest\":\"coin-digest-large\",\"balance\":\"42\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_exact",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[13]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameter = parsed.value.object.get("parameters").?.array.items[0].object;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-fit\\\"}\"",
        parameter.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-fit\\\"}\",13]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );

    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 2), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", preferred_commands.value.array.items[1].object.get("kind").?.string);
    const move_call_args = preferred_commands.value.array.items[1].object.get("arguments").?.array.items;
    try testing.expectEqual(@as(usize, 2), move_call_args.len);
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqual(@as(i64, 13), move_call_args[1].integer);

    const preferred_request = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_tx_dry_run_request_json").?.string,
        .{},
    );
    defer preferred_request.deinit();
    const request_commands = preferred_request.value.object.get("commands").?.array.items;
    try testing.expectEqualStrings("SplitCoins", request_commands[0].object.get("kind").?.string);

    const preferred_argv = template.get("preferred_tx_dry_run_argv").?.array.items;
    try testing.expectEqualStrings("tx", preferred_argv[0].string);
    try testing.expectEqualStrings("dry-run", preferred_argv[1].string);
    try testing.expectEqualStrings("--commands", preferred_argv[2].string);
}

test "runCommand move function with --summarize merges covering scalar coin candidates before split" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-small\",\"version\":\"9\",\"digest\":\"coin-digest-small\",\"balance\":\"3\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-mid\",\"version\":\"10\",\"digest\":\"coin-digest-mid\",\"balance\":\"5\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"11\",\"digest\":\"coin-digest-large\",\"balance\":\"9\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_exact",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[13]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 3), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("MergeCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", preferred_commands.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-large\",\"inputKind\":\"imm_or_owned\",\"version\":11,\"digest\":\"coin-digest-large\"}",
        preferred_commands.value.array.items[0].object.get("destination").?.string,
    );
    const merge_sources = preferred_commands.value.array.items[0].object.get("sources").?.array.items;
    try testing.expectEqual(@as(usize, 1), merge_sources.len);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-mid\",\"inputKind\":\"imm_or_owned\",\"version\":10,\"digest\":\"coin-digest-mid\"}",
        merge_sources[0].string,
    );
    const move_call_args = preferred_commands.value.array.items[2].object.get("arguments").?.array.items;
    try testing.expectEqual(@as(i64, 1), move_call_args[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqual(@as(i64, 13), move_call_args[1].integer);

    const preferred_argv = template.get("preferred_tx_dry_run_argv").?.array.items;
    try testing.expectEqualStrings("--commands", preferred_argv[2].string);
}

test "runCommand move function with --summarize plans split commands for multiple trailing scalar coin amounts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7\",\"module\":\"usdc\",\"name\":\"USDC\",\"typeParams\":[]}}]}},\"u64\",\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            if (std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xsui-fit\",\"version\":\"9\",\"digest\":\"sui-digest-fit\",\"balance\":\"11\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC\",\"coinObjectId\":\"0xusdc-fit\",\"version\":\"10\",\"digest\":\"usdc-digest-fit\",\"balance\":\"5\"}],\"hasNextPage\":false}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_two_exact",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[11,5]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xsui-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"sui-digest-fit\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xusdc-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"usdc-digest-fit\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xsui-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"sui-digest-fit\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xusdc-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"usdc-digest-fit\\\"}\",11,5]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );

    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 3), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", preferred_commands.value.array.items[2].object.get("kind").?.string);
    const move_call_args = preferred_commands.value.array.items[2].object.get("arguments").?.array.items;
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqual(@as(i64, 1), move_call_args[1].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), move_call_args[1].object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqual(@as(i64, 11), move_call_args[2].integer);
    try testing.expectEqual(@as(i64, 5), move_call_args[3].integer);
}

test "runCommand move function with --summarize avoids reusing the same scalar coin across parameters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},\"u64\",\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xsui-fit\",\"version\":\"9\",\"digest\":\"sui-digest-fit\",\"balance\":\"11\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xsui-next\",\"version\":\"10\",\"digest\":\"sui-digest-next\",\"balance\":\"13\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_two_same_exact",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[11,11]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xsui-fit\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"sui-digest-fit\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xsui-next\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"sui-digest-next\\\"}\"",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );

    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 3), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xsui-fit\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"sui-digest-fit\"}",
        preferred_commands.value.array.items[0].object.get("coin").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xsui-next\",\"inputKind\":\"imm_or_owned\",\"version\":10,\"digest\":\"sui-digest-next\"}",
        preferred_commands.value.array.items[1].object.get("coin").?.string,
    );
}

test "runCommand move function with --summarize avoids reusing scalar coins in later vector coin params" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"9\",\"digest\":\"coin-digest-large\",\"balance\":\"9\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-mid\",\"version\":\"10\",\"digest\":\"coin-digest-mid\",\"balance\":\"5\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_one_and_many",
        .tx_build_sender = "0xowner",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-large\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\"]",
        parameters[1].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-large\\\"}\",[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\"]]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function with --summarize reserves later explicit scalar coin args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"9\",\"digest\":\"coin-digest-large\",\"balance\":\"9\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-mid\",\"version\":\"10\",\"digest\":\"coin-digest-mid\",\"balance\":\"5\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "router",
        "deposit_pair",
        "--sender",
        "0xowner",
        "--arg-at",
        "1",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-large\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"coin-digest-large\"}",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\"",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-large\\\"}\"",
        parameters[1].object.get("explicit_arg_json").?.string,
    );
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":9,\\\"digest\\\":\\\"coin-digest-large\\\"}\"]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move function preferred split planning reserves later explicit scalar coin args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"9\",\"digest\":\"coin-digest-large\",\"balance\":\"9\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-mid\",\"version\":\"10\",\"digest\":\"coin-digest-mid\",\"balance\":\"5\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "move",
        "function",
        "0x2",
        "router",
        "deposit_pair_exact",
        "--sender",
        "0xowner",
        "--arg-at",
        "1",
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-large\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"coin-digest-large\"}",
        "--arg-at",
        "2",
        "5",
        "--summarize",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 2), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-mid\",\"inputKind\":\"imm_or_owned\",\"version\":10,\"digest\":\"coin-digest-mid\"}",
        preferred_commands.value.array.items[0].object.get("coin").?.string,
    );
    const move_call_args = preferred_commands.value.array.items[1].object.get("arguments").?.array.items;
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), move_call_args[0].object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-large\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"coin-digest-large\"}",
        move_call_args[1].string,
    );
    try testing.expectEqual(@as(i64, 5), move_call_args[2].integer);
}

test "runCommand move function with --summarize plans merge split make-move-vec for vector coin amount" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-small\",\"version\":\"9\",\"digest\":\"coin-digest-small\",\"balance\":\"3\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-mid\",\"version\":\"10\",\"digest\":\"coin-digest-mid\",\"balance\":\"5\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-large\",\"version\":\"11\",\"digest\":\"coin-digest-large\",\"balance\":\"9\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_many_exact",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[13]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-large\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":11,\\\"digest\\\":\\\"coin-digest-large\\\"}\",\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xcoin-mid\\\",\\\"inputKind\\\":\\\"imm_or_owned\\\",\\\"version\\\":10,\\\"digest\\\":\\\"coin-digest-mid\\\"}\"]",
        parameters[0].object.get("auto_selected_arg_json").?.string,
    );

    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 4), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("MergeCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("MakeMoveVec", preferred_commands.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", preferred_commands.value.array.items[3].object.get("kind").?.string);
    try testing.expect(preferred_commands.value.array.items[2].object.get("type").? == .null);

    const merge_sources = preferred_commands.value.array.items[0].object.get("sources").?.array.items;
    try testing.expectEqual(@as(usize, 1), merge_sources.len);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xcoin-mid\",\"inputKind\":\"imm_or_owned\",\"version\":10,\"digest\":\"coin-digest-mid\"}",
        merge_sources[0].string,
    );

    const make_move_vec_elements = preferred_commands.value.array.items[2].object.get("elements").?.array.items;
    try testing.expectEqual(@as(usize, 1), make_move_vec_elements.len);
    try testing.expectEqual(@as(i64, 1), make_move_vec_elements[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), make_move_vec_elements[0].object.get("NestedResult").?.array.items[1].integer);

    const move_call_args = preferred_commands.value.array.items[3].object.get("arguments").?.array.items;
    try testing.expectEqual(@as(i64, 2), move_call_args[0].object.get("Result").?.integer);
    try testing.expectEqual(@as(i64, 13), move_call_args[1].integer);
}

test "runCommand move function with --summarize plans dual vector coin templates by amount order" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[],\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"sui\",\"name\":\"SUI\",\"typeParams\":[]}}]}}},{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"Struct\":{\"address\":\"0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7\",\"module\":\"usdc\",\"name\":\"USDC\",\"typeParams\":[]}}]}}},\"u64\",\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }

            std.debug.assert(std.mem.eql(u8, req.method, "suix_getCoins"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            if (std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xsui-small\",\"version\":\"9\",\"digest\":\"sui-digest-small\",\"balance\":\"3\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xsui-mid\",\"version\":\"10\",\"digest\":\"sui-digest-mid\",\"balance\":\"5\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xsui-large\",\"version\":\"11\",\"digest\":\"sui-digest-large\",\"balance\":\"9\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.indexOf(u8, req.params_json, "\"0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC\"") != null) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC\",\"coinObjectId\":\"0xusdc-fit\",\"version\":\"12\",\"digest\":\"usdc-digest-fit\",\"balance\":\"7\"}],\"hasNextPage\":false}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_dual_many_exact",
        .tx_build_sender = "0xowner",
        .tx_build_args = "[13,7]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const template = parsed.value.object.get("call_template").?.object;
    const preferred_commands = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template.get("preferred_commands_json").?.string,
        .{},
    );
    defer preferred_commands.deinit();
    try testing.expectEqual(@as(usize, 6), preferred_commands.value.array.items.len);
    try testing.expectEqualStrings("MergeCoins", preferred_commands.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("MakeMoveVec", preferred_commands.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", preferred_commands.value.array.items[3].object.get("kind").?.string);
    try testing.expectEqualStrings("MakeMoveVec", preferred_commands.value.array.items[4].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", preferred_commands.value.array.items[5].object.get("kind").?.string);

    const move_call_args = preferred_commands.value.array.items[5].object.get("arguments").?.array.items;
    try testing.expectEqual(@as(i64, 2), move_call_args[0].object.get("Result").?.integer);
    try testing.expectEqual(@as(i64, 4), move_call_args[1].object.get("Result").?.integer);
    try testing.expectEqual(@as(i64, 13), move_call_args[2].integer);
    try testing.expectEqual(@as(i64, 7), move_call_args[3].integer);
}

test "runCommand move function with --summarize lifts coin selector min balance from explicit u64 args" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_function,
        .has_command = true,
        .move_package = "0x2",
        .move_module = "router",
        .move_function = "deposit_exact",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_args = "[13]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    const parameters = parsed.value.object.get("parameters").?.array.items;
    try testing.expectEqualStrings(
        "select:{\"kind\":\"coin_with_min_balance\",\"coinType\":\"0x2::sui::SUI\",\"minBalance\":13}",
        parameters[0].object.get("coin_with_min_balance_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":13}\"",
        parameters[0].object.get("placeholder_json").?.string,
    );
    try testing.expectEqualStrings("13", parameters[1].object.get("explicit_arg_json").?.string);
    try testing.expectEqualStrings(
        "[\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":13}\",13]",
        parsed.value.object.get("call_template").?.object.get("preferred_args_json").?.string,
    );
}

test "runCommand move package resolves aliases before issuing RPC" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var method_ok = false;
    var params_ok = false;
    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(ctx: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const mock: *MockContext = @ptrCast(@alignCast(ctx));
            mock.method_ok.* = std.mem.eql(u8, req.method, "sui_getNormalizedMoveModulesByPackage");
            mock.params_ok.* = std.mem.indexOf(u8, req.params_json, "\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\"") != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"pool\":{\"structs\":{\"Pool\":{},\"Tick\":{}},\"exposedFunctions\":{\"swap\":{},\"add_liquidity\":{}}}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .move_package,
        .has_command = true,
        .move_package = client.package_preset.cetus_clmm_mainnet,
        .tx_send_summarize = true,
    };
    var mock_ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings(client.package_preset.cetus_clmm_mainnet, parsed.value.object.get("package_id").?.string);
    try testing.expectEqualStrings("pool", parsed.value.object.get("modules").?.array.items[0].object.get("module_name").?.string);
    try testing.expectEqual(@as(i64, 2), parsed.value.object.get("modules").?.array.items[0].object.get("struct_count").?.integer);
}

test "runCommand object get with --summarize prints structured object summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xobject\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xobject\",\"version\":\"7\",\"digest\":\"digest-1\",\"type\":\"0x2::counter::Counter\",\"owner\":{\"AddressOwner\":\"0xowner\"},\"previousTransaction\":\"0xprev\",\"storageRebate\":\"42\"}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .object_get,
        .has_command = true,
        .object_id = "0xobject",
        .object_options = "{\"showType\":true}",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("found", parsed.value.object.get("status").?.string);
    try testing.expectEqualStrings("0xobject", parsed.value.object.get("object_id").?.string);
    try testing.expectEqualStrings("address_owner", parsed.value.object.get("owner_kind").?.string);
    try testing.expectEqualStrings("0xowner", parsed.value.object.get("owner_value").?.string);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xobject\",\"inputKind\":\"imm_or_owned\",\"version\":7,\"digest\":\"digest-1\"}",
        parsed.value.object.get("imm_or_owned_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0xobject\",\"inputKind\":\"receiving\",\"version\":7,\"digest\":\"digest-1\"}",
        parsed.value.object.get("receiving_object_input_select_token").?.string,
    );
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("shared_object_input_select_token").?);
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("mutable_shared_object_input_select_token").?);
}

test "runCommand account_info prints shared keystore json output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_info_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var args = cli.ParsedArgs{
        .command = .account_info,
        .has_command = true,
        .account_selector = "main",
        .account_info_json = true,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("sk_obj", parsed.value.object.get("entry").?.object.get("selector").?.string);
    try testing.expectEqualStrings("0x123", parsed.value.object.get("entry").?.object.get("address").?.string);
}

test "runCommand account_list prints raw keystore json output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_list_raw_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();

    var args = cli.ParsedArgs{
        .command = .account_list,
        .has_command = true,
        .account_list_json = true,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("sk_obj", parsed.value.object.get("accounts").?.array.items[0].object.get("selector").?.string);
    try testing.expectEqualStrings("main", parsed.value.object.get("accounts").?.array.items[0].object.get("alias").?.string);
}

test "runCommand account_coins prints summarized coin output for selector" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_coins_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var saw_request = false;
    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getCoins");
            ctx.params_ok.* = std.mem.eql(u8, req.params_json, "[\"0x123\",\"0x2::sui::SUI\",null,2]");
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-1\",\"balance\":\"7\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();
    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var args = cli.ParsedArgs{
        .command = .account_coins,
        .has_command = true,
        .account_selector = "main",
        .account_coin_type = "0x2::sui::SUI",
        .account_coins_limit = 2,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expect(params_ok);
    try testing.expectEqualStrings("0xcoin-1", parsed.value.object.get("entries").?.array.items[0].object.get("coin_object_id").?.string);
    try testing.expectEqualStrings("7", parsed.value.object.get("entries").?.array.items[0].object.get("balance").?.string);
}

test "runCommand account_objects prints summarized owned-object output for selector" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_objects_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var saw_request = false;
    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getOwnedObjects");
            if (std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{})) |parsed| {
                defer parsed.deinit();
                ctx.params_ok.* = blk: {
                    if (parsed.value != .array) break :blk false;
                    const items = parsed.value.array.items;
                    if (items.len != 4) break :blk false;
                    if (items[0] != .string or !std.mem.eql(u8, items[0].string, "0x123")) break :blk false;
                    if (items[1] != .object) break :blk false;
                    if (!std.mem.eql(u8, items[1].object.get("filter").?.object.get("StructType").?.string, "0x2::coin::Coin<0x2::sui::SUI>")) break :blk false;
                    if (items[1].object.get("options") == null) break :blk false;
                    if (items[1].object.get("options").?.object.get("showType") == null or
                        items[1].object.get("options").?.object.get("showOwner") == null) break :blk false;
                    if (items[2] != .null) break :blk false;
                    if (items[3] != .integer or items[3].integer != 2) break :blk false;
                    break :blk true;
                };
            } else |_| {
                ctx.params_ok.* = false;
            }
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xowned-1\",\"version\":\"7\",\"digest\":\"digest-1\",\"type\":\"0x2::coin::Coin<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0x123\"},\"previousTransaction\":\"prev-1\",\"storageRebate\":\"9\"}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();
    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var args = cli.ParsedArgs{
        .command = .account_objects,
        .has_command = true,
        .account_selector = "main",
        .account_objects_struct_type = "0x2::coin::Coin<0x2::sui::SUI>",
        .account_objects_limit = 2,
        .object_show_type = true,
        .object_show_owner = true,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expect(params_ok);
    try testing.expectEqualStrings("0xowned-1", parsed.value.object.get("entries").?.array.items[0].object.get("object_id").?.string);
    try testing.expectEqualStrings("0x2::coin::Coin<0x2::sui::SUI>", parsed.value.object.get("entries").?.array.items[0].object.get("type_name").?.string);
}

test "runCommand account_objects supports typed move-module filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_objects_module_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getOwnedObjects");
            ctx.params_ok.* = std.mem.indexOf(
                u8,
                req.params_json,
                "\"MoveModule\":{\"package\":\"0x2\",\"module\":\"coin\"}",
            ) != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xowned-1\",\"type\":\"0x2::coin::Coin<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var args = cli.ParsedArgs{
        .command = .account_objects,
        .has_command = true,
        .account_selector = "main",
        .account_objects_package = "0x2",
        .account_objects_module = "coin",
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);
}

test "runCommand account_objects resolves package aliases inside typed move-module filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_objects_module_alias_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getOwnedObjects");
            ctx.params_ok.* = std.mem.indexOf(
                u8,
                req.params_json,
                "\"MoveModule\":{\"package\":\"0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3\",\"module\":\"pool\"}",
            ) != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const argv = [_][]const u8{
        "account",
        "objects",
        "main",
        "--package",
        "cetus_clmm_mainnet",
        "--module",
        "pool",
    };
    var args = try cli.parseCliArgs(allocator, &argv);
    defer args.deinit(allocator);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);
}

test "runCommand account_objects supports typed object-id filters" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_objects_object_id_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getOwnedObjects");
            ctx.params_ok.* = std.mem.indexOf(
                u8,
                req.params_json,
                "\"ObjectId\":\"0xobject-1\"",
            ) != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xobject-1\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var args = cli.ParsedArgs{
        .command = .account_objects,
        .has_command = true,
        .account_selector = "main",
        .account_objects_object_id = "0xobject-1",
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);
}

test "runCommand account_resources prints summarized combined resource discovery output for selector" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_account_resources_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var request_count: usize = 0;
    var coins_request_ok = false;
    var objects_request_ok = false;

    const MockContext = struct {
        request_count: *usize,
        coins_request_ok: *bool,
        objects_request_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.request_count.* += 1;
            if (ctx.request_count.* == 1) {
                ctx.coins_request_ok.* = std.mem.eql(u8, req.method, "suix_getCoins") and
                    std.mem.eql(u8, req.params_json, "[\"0x123\",\"0x2::sui::SUI\",null,2]");
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xcoin-1\",\"balance\":\"7\"}],\"hasNextPage\":false}}",
                );
            }
            ctx.objects_request_ok.* = std.mem.eql(u8, req.method, "suix_getOwnedObjects") and
                std.mem.indexOf(u8, req.params_json, "\"StructType\":\"0x2::coin::Coin<0x2::sui::SUI>\"") != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xowned-1\",\"type\":\"0x2::coin::Coin<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();
    var ctx = MockContext{
        .request_count = &request_count,
        .coins_request_ok = &coins_request_ok,
        .objects_request_ok = &objects_request_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var args = cli.ParsedArgs{
        .command = .account_resources,
        .has_command = true,
        .account_selector = "main",
        .account_coin_type = "0x2::sui::SUI",
        .account_objects_struct_type = "0x2::coin::Coin<0x2::sui::SUI>",
        .account_resources_limit = 2,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 2), request_count);
    try testing.expect(coins_request_ok);
    try testing.expect(objects_request_ok);
    try testing.expect(parsed.value.object.get("coins") != null);
    try testing.expect(parsed.value.object.get("owned_objects") != null);
    try testing.expectEqualStrings("0xcoin-1", parsed.value.object.get("coins").?.object.get("entries").?.array.items[0].object.get("coin_object_id").?.string);
    try testing.expectEqualStrings("0xowned-1", parsed.value.object.get("owned_objects").?.object.get("entries").?.array.items[0].object.get("object_id").?.string);
}

test "runCommand account_list prints shared keystore summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_commands_run_account_list_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[\"sk_raw\",{\"alias\":\"main\",\"privateKey\":\"sk_obj\",\"address\":\"0x123\"}]");

    var rpc = try client.SuiRpcClient.init(allocator, "http://localhost:1234");
    defer rpc.deinit();

    var args = cli.ParsedArgs{
        .command = .account_list,
        .has_command = true,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqualStrings(
        "[0] selector=sk_raw\n[1] selector=sk_obj alias=main address=0x123\n",
        output.items,
    );
}

test "runCommand object get with typed option flags and --summarize prints structured object summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"showStorageRebate\":true") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xobject\",\"version\":\"7\",\"digest\":\"digest-1\",\"type\":\"0x2::counter::Counter\",\"owner\":{\"AddressOwner\":\"0xowner\"},\"previousTransaction\":\"0xprev\",\"storageRebate\":\"42\"}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .object_get,
        .has_command = true,
        .object_id = "0xobject",
        .object_show_type = true,
        .object_show_owner = true,
        .object_show_storage_rebate = true,
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("found", parsed.value.object.get("status").?.string);
    try testing.expectEqualStrings("0xobject", parsed.value.object.get("object_id").?.string);
    try testing.expectEqualStrings("address_owner", parsed.value.object.get("owner_kind").?.string);
}

test "runCommand object get resolves object preset aliases before issuing RPC" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_getObject");
            ctx.params_ok.* = std.mem.indexOf(u8, req.params_json, "\"0x6\"") != null and
                std.mem.indexOf(u8, req.params_json, "\"showOwner\":true") != null and
                std.mem.indexOf(u8, req.params_json, "\"showType\":true") != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0x6\",\"version\":\"1\",\"digest\":\"digest-clock\",\"type\":\"0x2::clock::Clock\",\"owner\":{\"Shared\":{\"initial_shared_version\":1}}}}}",
            );
        }
    }.call;

    const argv = [_][]const u8{
        "object",
        "get",
        "clock",
        "--summarize",
    };
    var args = try cli.parseCliArgs(allocator, &argv);
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expect(method_ok);
    try testing.expect(params_ok);
    try testing.expectEqualStrings("0x2::clock::Clock", parsed.value.object.get("type_name").?.string);
    try testing.expectEqualStrings("shared", parsed.value.object.get("owner_kind").?.string);
    try testing.expectEqualStrings("1", parsed.value.object.get("owner_value").?.string);
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x6\",\"inputKind\":\"shared\",\"initialSharedVersion\":1,\"mutable\":false}",
        parsed.value.object.get("shared_object_input_select_token").?.string,
    );
    try testing.expectEqualStrings(
        "select:{\"kind\":\"object_input\",\"objectId\":\"0x6\",\"inputKind\":\"shared\",\"initialSharedVersion\":1,\"mutable\":true}",
        parsed.value.object.get("mutable_shared_object_input_select_token").?.string,
    );
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("imm_or_owned_object_input_select_token").?);
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("receiving_object_input_select_token").?);
}

test "runCommand object dynamic-fields with --all prints aggregated summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var request_count: usize = 0;

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const count = @as(*usize, @ptrCast(@alignCast(context)));
            count.* += 1;
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getDynamicFields"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xparent\"") != null);

            if (count.* == 1) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ",1]") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xowner\"},\"bcsName\":\"AQ==\",\"type\":\"DynamicField\",\"objectType\":\"0x2::example::Field\",\"objectId\":\"0xchild1\",\"version\":\"4\",\"digest\":\"digest-1\"}],\"nextCursor\":\"cursor-2\",\"hasNextPage\":true}}",
                );
            }

            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"cursor-2\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xowner2\"},\"bcsName\":\"Ag==\",\"type\":\"DynamicField\",\"objectType\":\"0x2::example::Field\",\"objectId\":\"0xchild2\",\"version\":\"5\",\"digest\":\"digest-2\"}],\"hasNextPage\":false}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .object_dynamic_fields,
        .has_command = true,
        .object_parent_id = "0xparent",
        .object_dynamic_fields_limit = 1,
        .object_dynamic_fields_all = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &request_count,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 2), request_count);
    try testing.expectEqual(@as(usize, 2), parsed.value.object.get("entries").?.array.items.len);
    try testing.expect(!parsed.value.object.get("has_next_page").?.bool);
    try testing.expectEqualStrings("0xchild2", parsed.value.object.get("entries").?.array.items[1].object.get("object_id").?.string);
}

test "runCommand object dynamic-fields with --summarize prints structured page summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getDynamicFields"));
            std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0xparent\",\"cursor-1\",25]"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"name\":{\"type\":\"address\",\"value\":\"0xowner\"},\"bcsName\":\"AQ==\",\"type\":\"DynamicField\",\"objectType\":\"0x2::example::Field\",\"objectId\":\"0xchild\",\"version\":\"4\",\"digest\":\"digest-1\"}],\"nextCursor\":\"cursor-2\",\"hasNextPage\":true}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .object_dynamic_fields,
        .has_command = true,
        .object_parent_id = "0xparent",
        .object_dynamic_fields_cursor = "cursor-1",
        .object_dynamic_fields_limit = 25,
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value.object.get("has_next_page").?.bool);
    try testing.expectEqualStrings("cursor-2", parsed.value.object.get("next_cursor").?.string);
    try testing.expectEqualStrings("0xchild", parsed.value.object.get("entries").?.array.items[0].object.get("object_id").?.string);
}

test "runCommand object dynamic-fields resolves object preset aliases before issuing RPC" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getDynamicFields");
            ctx.params_ok.* = std.mem.indexOf(
                u8,
                req.params_json,
                "\"0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f\"",
            ) != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[],\"hasNextPage\":false}}",
            );
        }
    }.call;

    const argv = [_][]const u8{
        "object",
        "dynamic-fields",
        "preset:cetus.mainnet.clmm.global_config",
        "--limit",
        "1",
        "--summarize",
    };
    var args = try cli.parseCliArgs(allocator, &argv);
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);
}

test "runCommand object dynamic-field-object with --summarize prints structured object summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getDynamicFieldObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xparent\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xchild\",\"version\":\"9\",\"digest\":\"digest-child\",\"type\":\"0x2::example::Field\",\"owner\":{\"ObjectOwner\":\"0xparent\"},\"storageRebate\":\"11\"}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .object_dynamic_field_object,
        .has_command = true,
        .object_parent_id = "0xparent",
        .object_dynamic_field_name = "{\"type\":\"address\",\"value\":\"0xowner\"}",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("found", parsed.value.object.get("status").?.string);
    try testing.expectEqualStrings("0xchild", parsed.value.object.get("object_id").?.string);
    try testing.expectEqualStrings("object_owner", parsed.value.object.get("owner_kind").?.string);
    try testing.expectEqualStrings("0xparent", parsed.value.object.get("owner_value").?.string);
}

test "runCommand object dynamic-field-object with typed name flags and --summarize prints structured object summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getDynamicFieldObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"type\":\"address\"") != null);
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"value\":\"0xowner\"") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xchild\",\"version\":\"9\",\"digest\":\"digest-child\",\"type\":\"0x2::example::Field\",\"owner\":{\"ObjectOwner\":\"0xparent\"},\"storageRebate\":\"11\"}}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .object_dynamic_field_object,
        .has_command = true,
        .object_parent_id = "0xparent",
        .object_dynamic_field_name_type = "address",
        .object_dynamic_field_name_value = "\"0xowner\"",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("found", parsed.value.object.get("status").?.string);
    try testing.expectEqualStrings("0xchild", parsed.value.object.get("object_id").?.string);
    try testing.expectEqualStrings("object_owner", parsed.value.object.get("owner_kind").?.string);
    try testing.expectEqualStrings("0xparent", parsed.value.object.get("owner_value").?.string);
}

test "runCommand object dynamic-field-object resolves object preset aliases before issuing RPC" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "suix_getDynamicFieldObject");
            ctx.params_ok.* = std.mem.indexOf(
                u8,
                req.params_json,
                "\"0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f\"",
            ) != null;
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xchild\",\"version\":\"9\",\"digest\":\"digest-child\",\"type\":\"0x2::example::Field\",\"owner\":{\"ObjectOwner\":\"0xparent\"}}}}",
            );
        }
    }.call;

    const argv = [_][]const u8{
        "object",
        "dynamic-field-object",
        "cetus_clmm_global_config_mainnet",
        "--name-type",
        "address",
        "--name-value",
        "\"0xowner\"",
        "--summarize",
    };
    var args = try cli.parseCliArgs(allocator, &argv);
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);
}

test "buildExecutePayload includes signatures and optional options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildExecutePayload(
        allocator,
        "base64-tx-bytes",
        &.{ "sig-a", "sig-b" },
        "{\"skipChecks\":true}",
    );
    defer allocator.free(payload);

    try testing.expectEqualStrings(
        "[\"base64-tx-bytes\",[\"sig-a\",\"sig-b\"],{\"skipChecks\":true}]",
        payload,
    );
}

test "buildExecutePayload rejects non-object options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(
        error.InvalidCli,
        buildExecutePayload(allocator, "base64-tx-bytes", &.{}, "[\"skipChecks\"]"),
    );
}

test "buildExecutePayload no signatures and no options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildExecutePayload(
        allocator,
        "base64-tx-bytes",
        &.{},
        null,
    );
    defer allocator.free(payload);

    try testing.expectEqualStrings("[\"base64-tx-bytes\",[]]", payload);
}

test "buildProgrammaticTxExecutePayload includes programmatic tx metadata" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildProgrammaticTxExecutePayload(
        allocator,
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        "0xabc",
        1200,
        9,
        &.{"sig-a"},
        "{\"skipChecks\":true}",
    );
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expect(parsed.value.array.items[0] == .string);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, parsed.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expect(tx_block.value == .object);
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), tx_block.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), tx_block.value.object.get("gasPrice").?.integer);

    const signatures = parsed.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
}

test "buildProgrammaticTxExecutePayload rejects invalid command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, buildProgrammaticTxExecutePayload(
        allocator,
        "{\"kind\":\"MoveCall\"}",
        null,
        null,
        null,
        &.{},
        null,
    ));
}

test "resolveProgrammaticCommandsFromArgs builds move-call command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        null,
        "0x2",
        "counter",
        "increment",
        "[]",
        "[\"0xabc\"]",
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
}

test "resolveProgrammaticCommandsFromArgs validates explicit command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "{\"kind\":\"CustomFutureCommand\",\"value\":1}",
        null,
        null,
        null,
        null,
        null,
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    try testing.expectEqualStrings("CustomFutureCommand", parsed.value.array.items[0].object.get("kind").?.string);
}

test "resolveProgrammaticCommandsFromArgs accepts single command object and normalizes to array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
        null,
        null,
        null,
        null,
        null,
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    const command = parsed.value.array.items[0].object;
    const kind = command.get("kind") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("MoveCall", kind.string);
}

test "resolveProgrammaticCommandsFromArgs validates command object shape" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[\"MoveCall\"]",
        null,
        null,
        null,
        null,
        null,
    ));
    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[{\"package\":\"0x2\",\"module\":\"m\",\"function\":\"f\"}]",
        null,
        null,
        null,
        null,
        null,
    ));
    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[{\"kind\":\"MoveCall\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[]}]",
        null,
        null,
        null,
        null,
        null,
    ));
    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"]}]",
        null,
        null,
        null,
        null,
        null,
    ));
}

test "resolveProgrammaticCommandsFromArgs rejects empty command array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, resolveProgrammaticCommandsFromArgs(
        allocator,
        &.{},
        "[]",
        null,
        null,
        null,
        null,
        null,
    ));
}

test "resolveProgrammaticCommandsFromArgs merges --command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const fragment_items = [_][]const u8{
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}",
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
    };

    const commands = try resolveProgrammaticCommandsFromArgs(
        allocator,
        &fragment_items,
        "[{\"kind\":\"MoveCall\",\"package\":\"0x1\",\"module\":\"mod\",\"function\":\"f\",\"typeArguments\":[],\"arguments\":[]}]",
        null,
        null,
        null,
        null,
        null,
    );
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[2].object.get("kind").?.string);
}

test "supportsProgrammableInput detects command and move-call shapes" {
    const testing = std.testing;

    const no_args = cli.ParsedArgs{};
    try testing.expect(!cli.supportsProgrammableInput(&no_args));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var command_item_args = cli.ParsedArgs{};
    defer command_item_args.deinit(allocator);
    try command_item_args.tx_build_command_items.append(allocator, "{}");
    try testing.expect(cli.supportsProgrammableInput(&command_item_args));

    const command_args = cli.ParsedArgs{ .tx_build_commands = "[]", .tx_build_package = "0x2", .tx_build_module = "m", .tx_build_function = "f" };
    try testing.expect(cli.supportsProgrammableInput(&command_args));

    const move_call_args = cli.ParsedArgs{ .tx_build_package = "0x2", .tx_build_module = "m", .tx_build_function = "f" };
    try testing.expect(cli.supportsProgrammableInput(&move_call_args));
}

test "buildProgrammaticTxSimulatePayload includes gas and sender context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildProgrammaticTxSimulatePayload(
        allocator,
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        "0xabc",
        1200,
        9,
        "{\"skipChecks\":true}",
    );
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expect(parsed.value.array.items[0] == .string);

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, parsed.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", tx_block.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), tx_block.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), tx_block.value.object.get("gasPrice").?.integer);

    const context = parsed.value.array.items[1].object;
    try testing.expectEqualStrings("0xabc", context.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1200), context.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), context.get("gasPrice").?.integer);
    try testing.expect(context.get("options") != null);
    try testing.expect(context.get("options").?.object.get("skipChecks") != null);
}

test "runCommand tx_simulate with commands sends inspect request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_options = "{\"skipChecks\":true}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}\n", output.items);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 2), params.value.array.items.len);

    const context = params.value.array.items[1].object;
    try testing.expectEqualStrings("0xabc", context.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), context.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 7), context.get("gasPrice").?.integer);
    try testing.expect(context.get("options") != null);
}

test "runCommand tx_simulate move-call sends inspect request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 11,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct { saw_request: *bool, params_text: *?[]const u8 };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            _ = req.method;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":true}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();

    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", tx_block.value.object.get("kind").?.string);
    const commands = tx_block.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    const instruction = commands.items[0];
    try testing.expectEqualStrings("MoveCall", instruction.object.get("kind").?.string);
}

test "runCommand tx_simulate accepts single command object input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"ok\":true}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    const commands = tx_block.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
}

test "runCommand tx_simulate rejects incomplete move-call context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_payload with commands builds execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var unsafe_batch_calls: usize = 0;
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const count = @as(*usize, @ptrCast(@alignCast(context)));
            if (!std.mem.eql(u8, req.method, "unsafe_batchTransaction")) return error.OutOfMemory;
            count.* += 1;

            const params = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
            defer params.deinit();
            std.debug.assert(std.mem.eql(u8, params.value.array.items[0].string, "0xabc"));
            std.debug.assert(params.value.array.items[2] == .null);
            std.debug.assert(std.mem.eql(u8, params.value.array.items[3].string, "1200"));

            return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
        }
    }.call;
    rpc.request_sender = .{
        .context = &unsafe_batch_calls,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 1), unsafe_batch_calls);
    try testing.expect(payload.value == .array);
    const items = payload.value.array.items;
    try testing.expectEqual(@as(usize, 2), items.len);
    try testing.expectEqualStrings("AQIDBA==", items[0].string);

    try testing.expect(items[1] == .array);
    const signatures = items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
}

test "runCommand tx_payload with explicit gas payment uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"13\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { object: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"owner\":{\"AddressOwner\":\"0xabc\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_payload with auto gas payment selects gasPayment from rpc" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct { gas_price_calls: usize = 0, coin_calls: usize = 0, object_calls: usize = 0, unsafe_batch_calls: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, "suix_getReferenceGasPrice", req.method)) {
                st.gas_price_calls += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, "suix_getCoins", req.method)) {
                st.coin_calls += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x101\",\"version\":\"14\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"balance\":\"5\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x102\",\"version\":\"15\",\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"balance\":\"1200\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, "sui_getObject", req.method)) {
                st.object_calls += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"owner\":{\"AddressOwner\":\"0xabc\"}}}}",
                );
            }
            if (std.mem.eql(u8, "unsafe_batchTransaction", req.method)) {
                st.unsafe_batch_calls += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_auto_gas_payment = true,
        .tx_build_gas_payment_min_balance = 100,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), state.gas_price_calls);
    try testing.expectEqual(@as(usize, 1), state.coin_calls);
    try testing.expectEqual(@as(usize, 1), state.object_calls);
    try testing.expectEqual(@as(usize, 0), state.unsafe_batch_calls);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_build move-call with auto gas payment excludes selected business SUI coin from gas payment" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct { normalized: usize = 0, coin: usize = 0, object: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"visibility\":\"Public\",\"isEntry\":true,\"typeParameters\":[[]],\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}},\"u64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                state.coin += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xb1b1\",\"version\":\"9\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"balance\":\"150\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xc2c2\",\"version\":\"10\",\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"balance\":\"500\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xb1b1") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xb1b1\",\"version\":\"9\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"type\":\"0x2::coin::Coin<0x2::sui::SUI>\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "router",
        .tx_build_function = "deposit_exact",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"coin_with_min_balance\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"coinType\\\":\\\"0x2::sui::SUI\\\",\\\"minBalance\\\":100}\",13]",
        .tx_build_sender = "0xowner",
        .tx_build_gas_budget = 50,
        .tx_build_gas_price = 7,
        .tx_build_auto_gas_payment = true,
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 0), counts.normalized);
    try testing.expectEqual(@as(usize, 2), counts.coin);
    try testing.expectEqual(@as(usize, 0), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"gasPayment\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"objectId\":\"0xc2c2\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"gasPayment\":[{\"objectId\":\"0xb1b1\"") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xb1b1") != null);
}

test "runCommand tx_build commands with auto gas payment excludes multi-coin business SUI inputs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct { coin: usize = 0 };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                state.coin += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0xowner\"") != null);
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "\"0x2::sui::SUI\"") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xb1b1\",\"version\":\"9\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"balance\":\"150\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xb2b2\",\"version\":\"10\",\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"balance\":\"200\"},{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xc3c3\",\"version\":\"11\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"balance\":\"500\"}],\"hasNextPage\":false}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands =
        \\[
        \\  {"kind":"MergeCoins","destination":"select:{\"kind\":\"object_input\",\"objectId\":\"0xb1b1\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}","sources":["select:{\"kind\":\"object_input\",\"objectId\":\"0xb2b2\",\"inputKind\":\"imm_or_owned\",\"version\":10,\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\"}"]},
        \\  {"kind":"SplitCoins","coin":"select:{\"kind\":\"object_input\",\"objectId\":\"0xb1b1\",\"inputKind\":\"imm_or_owned\",\"version\":9,\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}","amounts":[13]},
        \\  {"kind":"MakeMoveVec","type":null,"elements":[{"NestedResult":[1,0]}]},
        \\  {"kind":"MoveCall","package":"0x2","module":"router","function":"deposit_many_exact","typeArguments":[{"Struct":{"address":"0x2","module":"sui","name":"SUI","typeParams":[]}}],"arguments":[{"Result":2}]}
        \\]
        ,
        .tx_build_sender = "0xowner",
        .tx_build_gas_budget = 50,
        .tx_build_gas_price = 7,
        .tx_build_auto_gas_payment = true,
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.coin);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"gasPayment\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"objectId\":\"0xc3c3\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"gasPayment\":[{\"objectId\":\"0xb1b1\"") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"gasPayment\":[{\"objectId\":\"0xb2b2\"") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xb1b1") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xb2b2") != null);
}

test "runCommand tx_payload infers sender for auto gas payment from selected owner" {
    const testing = std.testing;
    const Counts = struct { gas_price: usize = 0, owned: usize = 0, coin: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                state.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"9\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                state.owned += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x123") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x1ee7ed\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                state.coin += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x123") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x201\",\"version\":\"17\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"balance\":\"800\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x1ee7ed") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x1ee7ed\",\"version\":\"18\",\"digest\":\"0x5555555555555555555555555555555555555555555555555555555555555555\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0x123\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 500,
        .tx_build_auto_gas_payment = true,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();

    try testing.expectEqual(@as(usize, 1), counts.gas_price);
    try testing.expectEqual(@as(usize, 1), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.coin);
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_payload with selected gas payment token resolves gasPayment from rpc" {
    const testing = std.testing;
    const Counts = struct { gas_price: usize = 0, coin: usize = 0, object: usize = 0, unsafe: usize = 0 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                state.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                state.coin += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x301\",\"version\":\"16\",\"digest\":\"0x6666666666666666666666666666666666666666666666666666666666666666\",\"balance\":\"500\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"19\",\"digest\":\"0x7777777777777777777777777777777777777777777777777777777777777777\",\"owner\":{\"AddressOwner\":\"0xabc\"}}}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "select:{\"kind\":\"gas_coin\",\"minBalance\":100}",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 1), counts.gas_price);
    try testing.expectEqual(@as(usize, 1), counts.coin);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_payload infers sender from selected gas payment owner" {
    const testing = std.testing;
    const Counts = struct { gas_price: usize = 0, owned: usize = 0, coin: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "select:{\"kind\":\"gas_coin\",\"owner\":\"0x123\",\"minBalance\":100}",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                state.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                state.coin += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x123") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x401\",\"version\":\"22\",\"digest\":\"0x8888888888888888888888888888888888888888888888888888888888888888\",\"balance\":\"500\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                state.owned += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x123") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x0abcde\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x0abcde") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x0abcde\",\"version\":\"23\",\"digest\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();

    try testing.expectEqual(@as(usize, 1), counts.gas_price);
    try testing.expectEqual(@as(usize, 1), counts.coin);
    try testing.expectEqual(@as(usize, 1), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_payload with commands and --summarize prints payload summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_send_summarize = true,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var unsafe_batch_calls: usize = 0;
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const count = @as(*usize, @ptrCast(@alignCast(context)));
            if (!std.mem.eql(u8, req.method, "unsafe_batchTransaction")) return error.OutOfMemory;
            count.* += 1;
            return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
        }
    }.call;
    rpc.request_sender = .{
        .context = &unsafe_batch_calls,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), unsafe_batch_calls);

    const summary = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer summary.deinit();
    try testing.expectEqualStrings("tx_bytes", summary.value.object.get("data_kind").?.string);
    try testing.expectEqual(@as(i64, 1), summary.value.object.get("signature_count").?.integer);
    try testing.expectEqual(@as(i64, 2), summary.value.object.get("payload_items_count").?.integer);
}

test "runCommand tx_payload with commands resolves selected argument tokens into execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { owned: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                state.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xa1b2c3\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                const params = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer params.deinit();
                const move_call = params.value.array.items[1].array.items[0].object.get("moveCallRequestParams").?.object;
                std.debug.assert(std.mem.eql(u8, move_call.get("arguments").?.array.items[0].string, "0xa1b2c3"));
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 2), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.unsafe);
    try testing.expectEqualStrings("[\"AQIDBA==\",[\"sig-a\"]]\n", output.items);
}

test "runCommand tx_payload move-call builds execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var unsafe_move_calls: usize = 0;
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const count = @as(*usize, @ptrCast(@alignCast(context)));
            if (!std.mem.eql(u8, req.method, "unsafe_moveCall")) return error.OutOfMemory;
            count.* += 1;

            const params = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
            defer params.deinit();
            std.debug.assert(std.mem.eql(u8, params.value.array.items[0].string, "0xabc"));
            std.debug.assert(params.value.array.items[6] == .null);
            std.debug.assert(std.mem.eql(u8, params.value.array.items[7].string, "1200"));

            return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
        }
    }.call;
    rpc.request_sender = .{
        .context = &unsafe_move_calls,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 1), unsafe_move_calls);
    try testing.expect(payload.value == .array);
    try testing.expectEqualStrings("AQIDBA==", payload.value.array.items[0].string);
    try testing.expect(payload.value.array.items[1].array.items.len == 1);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_payload move-call resolves selected argument tokens into execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { owned: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                state.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc123\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                state.unsafe += 1;
                const params = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer params.deinit();
                std.debug.assert(std.mem.eql(u8, params.value.array.items[0].string, "0xabc"));
                const call_args = params.value.array.items[5].array.items;
                std.debug.assert(std.mem.eql(u8, call_args[0].string, "0xabc123"));
                std.debug.assert(call_args[1].integer == 7);
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 2), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.unsafe);
    try testing.expect(payload.value == .array);
    try testing.expectEqualStrings("AQIDBA==", payload.value.array.items[0].string);
}

test "runCommand tx_payload move-call resolves ownerless selected tokens from default keystore sender" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x23} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_selected_ownerless_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var request_count: usize = 0;
    const MockContext = struct {
        request_count: *usize,
        expected_sender: []const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.request_count.* += 1;
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ctx.expected_sender) != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xbad1d0\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xbad1d0\"}}}],\"hasNextPage\":false}}",
                );
            }
            std.debug.assert(std.mem.eql(u8, req.method, "unsafe_moveCall"));
            return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
        }
    }.call;
    var mock_ctx = MockContext{
        .request_count = &request_count,
        .expected_sender = expected_sender,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 3), request_count);
    try testing.expect(payload.value == .array);
    try testing.expectEqualStrings("AQIDBA==", payload.value.array.items[0].string);
    const signature = payload.value.array.items[1].array.items[0].string;
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(signature);
    try testing.expectEqual(@as(usize, 97), decoded_len);
}

test "runCommand tx_payload move-call with from-keystore uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x24} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_unsafe_move_call_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0x1111111111111111111111111111111111111111111111111111111111111111\"]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const MockContext = struct {
        gas_price: usize = 0,
        normalized: usize = 0,
        object: usize = 0,
        unsafe: usize = 0,
        expected_sender: []const u8,
    };
    var mock_ctx = MockContext{ .expected_sender = expected_sender };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x1111111111111111111111111111111111111111111111111111111111111111") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"5\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe += 1;
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), mock_ctx.gas_price);
    try testing.expectEqual(@as(usize, 1), mock_ctx.normalized);
    try testing.expectEqual(@as(usize, 1), mock_ctx.object);
    try testing.expectEqual(@as(usize, 0), mock_ctx.unsafe);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    const signature = payload.value.array.items[1].array.items[0].string;
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(signature);
    try testing.expectEqual(@as(usize, 97), decoded_len);
}

test "runCommand tx_payload move-call with from-keystore resolves selected argument tokens through local programmable builder" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x44} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_unsafe_move_call_selected_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var gas_price_queries: usize = 0;
    var owned_object_queries: usize = 0;
    var normalized_queries: usize = 0;
    var object_queries: usize = 0;
    var unsafe_calls: usize = 0;
    const MockContext = struct {
        gas_price_queries: *usize,
        owned_object_queries: *usize,
        normalized_queries: *usize,
        object_queries: *usize,
        unsafe_calls: *usize,
        expected_sender: []const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price_queries.* += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                ctx.owned_object_queries.* += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ctx.expected_sender) != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized_queries.* += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.object_queries.* += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x2222222222222222222222222222222222222222222222222222222222222222") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"5\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe_calls.* += 1;
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{
        .gas_price_queries = &gas_price_queries,
        .owned_object_queries = &owned_object_queries,
        .normalized_queries = &normalized_queries,
        .object_queries = &object_queries,
        .unsafe_calls = &unsafe_calls,
        .expected_sender = expected_sender,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), gas_price_queries);
    try testing.expectEqual(@as(usize, 1), owned_object_queries);
    try testing.expectEqual(@as(usize, 1), normalized_queries);
    try testing.expectEqual(@as(usize, 1), object_queries);
    try testing.expectEqual(@as(usize, 0), unsafe_calls);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_payload move-call with from-keystore resolves selected gas payment tokens through local programmable builder" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x45} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_unsafe_move_call_gas_selected_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0x1111111111111111111111111111111111111111111111111111111111111111\"]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "select:{\"kind\":\"gas_coin\",\"minBalance\":1}",
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var gas_price_queries: usize = 0;
    var coin_queries: usize = 0;
    var normalized_queries: usize = 0;
    var object_queries: usize = 0;
    var unsafe_calls: usize = 0;
    const MockContext = struct {
        gas_price_queries: *usize,
        coin_queries: *usize,
        normalized_queries: *usize,
        object_queries: *usize,
        unsafe_calls: *usize,
        expected_sender: []const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price_queries.* += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                ctx.coin_queries.* += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ctx.expected_sender) != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"8\",\"digest\":\"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"balance\":\"900\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized_queries.* += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.object_queries.* += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x1111111111111111111111111111111111111111111111111111111111111111") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"5\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe_calls.* += 1;
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{
        .gas_price_queries = &gas_price_queries,
        .coin_queries = &coin_queries,
        .normalized_queries = &normalized_queries,
        .object_queries = &object_queries,
        .unsafe_calls = &unsafe_calls,
        .expected_sender = expected_sender,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), gas_price_queries);
    try testing.expectEqual(@as(usize, 1), coin_queries);
    try testing.expectEqual(@as(usize, 1), normalized_queries);
    try testing.expectEqual(@as(usize, 1), object_queries);
    try testing.expectEqual(@as(usize, 0), unsafe_calls);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_payload commands with from-keystore resolves selected tokens through local programmable builder" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x46} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_unsafe_batch_selected_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]},{\"kind\":\"TransferObjects\",\"objects\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::OtherThing\\\"}\"],\"address\":\"0x4444444444444444444444444444444444444444444444444444444444444444\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "select:{\"kind\":\"gas_coin\",\"minBalance\":1}",
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var gas_price_queries: usize = 0;
    var owned_object_queries: usize = 0;
    var coin_queries: usize = 0;
    var normalized_queries: usize = 0;
    var object_queries: usize = 0;
    var unsafe_batch_calls: usize = 0;
    const MockContext = struct {
        gas_price_queries: *usize,
        owned_object_queries: *usize,
        coin_queries: *usize,
        normalized_queries: *usize,
        object_queries: *usize,
        unsafe_batch_calls: *usize,
        expected_sender: []const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price_queries.* += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                ctx.owned_object_queries.* += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ctx.expected_sender) != null);
                if (std.mem.indexOf(u8, req.params_json, "OtherThing") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"type\":\"0x2::example::OtherThing\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                ctx.coin_queries.* += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, ctx.expected_sender) != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"8\",\"digest\":\"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"balance\":\"900\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized_queries.* += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.object_queries.* += 1;
                if (std.mem.indexOf(u8, req.params_json, "0x3333333333333333333333333333333333333333333333333333333333333333") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"6\",\"digest\":\"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"5\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction") or std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                ctx.unsafe_batch_calls.* += 1;
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{
        .gas_price_queries = &gas_price_queries,
        .owned_object_queries = &owned_object_queries,
        .coin_queries = &coin_queries,
        .normalized_queries = &normalized_queries,
        .object_queries = &object_queries,
        .unsafe_batch_calls = &unsafe_batch_calls,
        .expected_sender = expected_sender,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), gas_price_queries);
    try testing.expectEqual(@as(usize, 2), owned_object_queries);
    try testing.expectEqual(@as(usize, 1), coin_queries);
    try testing.expectEqual(@as(usize, 1), normalized_queries);
    try testing.expectEqual(@as(usize, 2), object_queries);
    try testing.expectEqual(@as(usize, 0), unsafe_batch_calls);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
}

test "runCommand tx_send commands with from-keystore uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x47} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_unsafe_batch_send_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[\"0x1111111111111111111111111111111111111111111111111111111111111111\",7]},{\"kind\":\"TransferObjects\",\"objects\":[\"0x2222222222222222222222222222222222222222222222222222222222222222\"],\"address\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct {
        gas_price: usize = 0,
        normalized: usize = 0,
        object: usize = 0,
        unsafe_batch_calls: usize = 0,
        execute_calls: usize = 0,
        expected_sender: []const u8,
    };
    var state = State{
        .expected_sender = expected_sender,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.object += 1;
                if (std.mem.indexOf(u8, req.params_json, "0x1111111111111111111111111111111111111111111111111111111111111111") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"5\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                    );
                }
                if (std.mem.indexOf(u8, req.params_json, "0x2222222222222222222222222222222222222222222222222222222222222222") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"6\",\"digest\":\"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"owner\":{\"AddressOwner\":\"0x2222222222222222222222222222222222222222222222222222222222222222\"}}}}",
                    );
                }
                return error.OutOfMemory;
            }
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction") or std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                ctx.unsafe_batch_calls += 1;
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_calls += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                const signature = payload.value.array.items[1].array.items[0].string;
                const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(signature) catch return error.OutOfMemory;
                std.debug.assert(decoded_len == 97);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xdeadbeef\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 2), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe_batch_calls);
    try testing.expectEqual(@as(usize, 1), state.execute_calls);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xdeadbeef", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommand tx_send request artifact with from-keystore uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x52} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);

    const keystore_path = "tmp_request_send_keystore.json";
    try std.fs.cwd().writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer std.fs.cwd().deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = try cli.parseCliArgs(allocator, &.{
        "tx",
        "send",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"fromKeystore\":true,\"signer\":\"0\",\"gasBudget\":1200,\"gasPayment\":[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}],\"summarize\":true}",
    });
    defer args.deinit(allocator);

    const State = struct {
        gas_price: usize = 0,
        normalized: usize = 0,
        execute_calls: usize = 0,
        unsafe_calls: usize = 0,
    };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_calls += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"digest\":\"0xsendrequest\",\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe_calls += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.execute_calls);
    try testing.expectEqual(@as(usize, 0), state.unsafe_calls);
}

test "runCommandWithProgrammaticProvider tx_send move-call with selected args uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const sender = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const State = struct { gas_price: usize = 0, owned: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                st.owned += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, sender) != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                st.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Thing\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x2222222222222222222222222222222222222222222222222222222222222222") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"9\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                std.debug.assert(std.mem.eql(u8, payload.value.array.items[1].array.items[0].string, "sig-provider"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xprovider-move\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .remote_signer = .{
                .address = sender,
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expect(req.tx_bytes_base64.?.len > 0);
                            return .{
                                .sender = sender,
                                .signatures = &.{"sig-provider"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "provider-session" },
                .session_supports_execute = true,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.owned);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xprovider-move", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_send commands with auto gas uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0x3333333333333333333333333333333333333333333333333333333333333333\"],\"address\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_auto_gas_payment = true,
        .tx_build_gas_payment_min_balance = 50,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const sender = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const State = struct { gas_price: usize = 0, coins: usize = 0, object: usize = 0, unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                st.coins += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, sender) != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"7\",\"digest\":\"0x5555555555555555555555555555555555555555555555555555555555555555\",\"balance\":\"90\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x3333333333333333333333333333333333333333333333333333333333333333") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"9\",\"digest\":\"0x6666666666666666666666666666666666666666666666666666666666666666\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                std.debug.assert(std.mem.eql(u8, payload.value.array.items[1].array.items[0].string, "sig-provider-auto"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xprovider-batch\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .remote_signer = .{
                .address = sender,
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expect(req.tx_bytes_base64.?.len > 0);
                            return .{
                                .sender = sender,
                                .signatures = &.{"sig-provider-auto"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "provider-auto-session" },
                .session_supports_execute = true,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.coins);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xprovider-batch", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_send move-call prints provider challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "generic-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-generic-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0xprovider\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_send move-call applies unsafe provider challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"generic-provider-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                st.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xgeneric-provider-approved\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "generic-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expectEqualStrings("generic-provider-approved", req.account_session.session_id.?);
                            return .{
                                .sender = "0xprovider",
                                .signatures = &.{"sig-generic-provider-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-generic-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.unsafe);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xgeneric-provider-approved", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_send commands prints provider challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "unsafe-batch-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-unsafe-batch-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0xprovider\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_send commands applies unsafe batch provider challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"unsafe-batch-provider-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                st.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xunsafe-batch-provider-approved\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "unsafe-batch-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expectEqualStrings("unsafe-batch-provider-approved", req.account_session.session_id.?);
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expectEqualStrings("AQIDBA==", req.tx_bytes_base64.?);
                            return .{
                                .sender = "0xprovider",
                                .signatures = &.{"sig-unsafe-batch-provider-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-unsafe-batch-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.unsafe);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xunsafe-batch-provider-approved", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_simulate move-call prints generic provider challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "simulate-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-simulate-provider",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0xprovider\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_simulate move-call with explicit gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { normalized: usize = 0, object: usize = 0, inspect: usize = 0 };
    var counts = Counts{};
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        counts: *Counts,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.counts.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.counts.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock")) {
                ctx.counts.inspect += 1;
                ctx.params_text.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{
        .counts = &counts,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "simulate-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-simulate-provider",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}\n", output.items);
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 1), counts.inspect);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("0x123", tx_block.value.object.get("sender").?.string);
    try testing.expect(tx_block.value.object.get("inputs") != null);
    try testing.expect(tx_block.value.object.get("gasData") != null);
}

test "runCommandWithProgrammaticProvider tx_simulate move-call with selected args and inferred gas price uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { gas_price: usize = 0, owned: usize = 0, normalized: usize = 0, object: usize = 0, inspect: usize = 0 };
    var counts = Counts{};
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        counts: *Counts,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.counts.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                ctx.counts.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc123\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.counts.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Thing\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.counts.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc123\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock")) {
                ctx.counts.inspect += 1;
                ctx.params_text.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{
        .counts = &counts,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "simulate-provider-selected-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-simulate-provider-selected",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 1), counts.gas_price);
    try testing.expectEqual(@as(usize, 1), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 1), counts.inspect);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    try testing.expect(captured.len > 0);
}

test "runCommandWithProgrammaticProvider tx_build programmable applies generic provider challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[\"0xabc\",7]}]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
        .tx_build_emit_tx_block = true,
        .tx_send_summarize = true,
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"build-provider-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "build-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expectEqualStrings("build-provider-approved", req.account_session.session_id.?);
                            return .{
                                .sender = "0xprovider",
                                .signatures = &.{"sig-build-provider-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-build-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"artifact_kind\":\"transaction_block\"") != null);
}

test "runCommandWithProgrammaticProvider tx_build programmable with explicit gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0x456\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"4\",\"digest\":\"0x5555555555555555555555555555555555555555555555555555555555555555\"}]",
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var object_calls: usize = 0;
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const calls = @as(*usize, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                calls.* += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xcoin\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &object_calls,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "build-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-build-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 1), object_calls);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0x123", parsed.value.object.get("sender").?.string);
    try testing.expect(parsed.value.object.get("inputs") != null);
    try testing.expect(parsed.value.object.get("gasData") != null);
}

test "runCommandWithProgrammaticProvider tx_payload move-call prints provider challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0xprovider",
        .tx_build_gas_budget = 1200,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "payload-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-payload-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0xprovider\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_payload move-call with selected args applies unsafe provider challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0xgas\",\"version\":\"1\",\"digest\":\"digest-gas\"}]",
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"payload-provider-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { owned: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                st.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc123\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xprovider\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                st.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0xprovider",
                .session = .{ .kind = .passkey, .session_id = "payload-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expectEqualStrings("AQIDBA==", req.tx_bytes_base64.?);
                            try testing.expectEqualStrings("payload-provider-approved", req.account_session.session_id.?);
                            return .{
                                .sender = "0xprovider",
                                .signatures = &.{"sig-payload-provider-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-payload-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.owned);
    try testing.expectEqual(@as(usize, 1), state.unsafe);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqualStrings("AQIDBA==", payload.value.array.items[0].string);
    try testing.expectEqualStrings("sig-payload-provider-approved", payload.value.array.items[1].array.items[0].string);
}

test "runCommandWithProgrammaticProvider tx_send move-call with selected args prints local builder provider challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const sender = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const State = struct { gas_price: usize = 0, owned: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                st.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                st.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Thing\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"9\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = sender,
                .session = .{ .kind = .passkey, .session_id = "provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-provider-session",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.owned);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expect(std.mem.indexOf(u8, output.items, sender) != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_send commands with auto gas prints local builder provider challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0x3333333333333333333333333333333333333333333333333333333333333333\"],\"address\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_auto_gas_payment = true,
        .tx_build_gas_payment_min_balance = 50,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const sender = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const State = struct { gas_price: usize = 0, coins: usize = 0, object: usize = 0, unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                st.coins += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"7\",\"digest\":\"0x5555555555555555555555555555555555555555555555555555555555555555\",\"balance\":\"90\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"9\",\"digest\":\"0x6666666666666666666666666666666666666666666666666666666666666666\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = sender,
                .session = .{ .kind = .passkey, .session_id = "provider-auto-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-provider-auto",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.coins);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expect(std.mem.indexOf(u8, output.items, sender) != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_send move-call with selected args applies local builder challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"provider-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const sender = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const State = struct { gas_price: usize = 0, owned: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                st.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                st.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"example\",\"name\":\"Thing\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"9\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                std.debug.assert(std.mem.eql(u8, payload.value.array.items[1].array.items[0].string, "sig-provider-approved"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xprovider-selected-approved\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = sender,
                .session = .{ .kind = .passkey, .session_id = "provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expect(req.tx_bytes_base64.?.len > 0);
                            try testing.expectEqualStrings("provider-approved", req.account_session.session_id.?);
                            return .{
                                .sender = sender,
                                .signatures = &.{"sig-provider-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-provider-session",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.owned);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xprovider-selected-approved", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_send commands with auto gas applies local builder challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0x3333333333333333333333333333333333333333333333333333333333333333\"],\"address\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_auto_gas_payment = true,
        .tx_build_gas_payment_min_balance = 50,
        .tx_session_response = "{\"supports_execute\":true,\"session\":{\"kind\":\"passkey\",\"session_id\":\"provider-auto-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const sender = "0x1111111111111111111111111111111111111111111111111111111111111111";
    const State = struct { gas_price: usize = 0, coins: usize = 0, object: usize = 0, unsafe: usize = 0, execute: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                st.coins += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"7\",\"digest\":\"0x5555555555555555555555555555555555555555555555555555555555555555\",\"balance\":\"90\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"9\",\"digest\":\"0x6666666666666666666666666666666666666666666666666666666666666666\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                std.debug.assert(std.mem.eql(u8, payload.value.array.items[1].array.items[0].string, "sig-provider-auto-approved"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xprovider-auto-approved\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = sender,
                .session = .{ .kind = .passkey, .session_id = "provider-auto-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expect(req.tx_bytes_base64.?.len > 0);
                            try testing.expectEqualStrings("provider-auto-approved", req.account_session.session_id.?);
                            return .{
                                .sender = sender,
                                .signatures = &.{"sig-provider-auto-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-provider-auto",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.coins);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xprovider-auto-approved", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommand tx_payload move-call with direct signatures and selected arguments uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0x123\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"1\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .tx_build_sender = "0x123",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { gas_price: usize = 0, owned: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                st.owned += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x123") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc123\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                st.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc123") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc123\",\"version\":\"9\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.owned);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_payload commands with direct signatures and selected arguments uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"arguments\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0x123\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]},{\"kind\":\"TransferObjects\",\"objects\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0x123\\\",\\\"structType\\\":\\\"0x2::example::OtherThing\\\"}\"],\"address\":\"0xdef\"}]",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"1\",\"digest\":\"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"}]",
        .tx_build_sender = "0x123",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { gas_price: usize = 0, owned: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                st.owned += 1;
                if (std.mem.indexOf(u8, req.params_json, "OtherThing") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xdef456\",\"type\":\"0x2::example::OtherThing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc123\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                st.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                st.object += 1;
                if (std.mem.indexOf(u8, req.params_json, "0xdef456") != null) {
                    return alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0xdef456\",\"version\":\"10\",\"digest\":\"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                    );
                }
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc123\",\"version\":\"9\",\"digest\":\"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 2), state.owned);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 2), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_payload move-call with direct signatures and gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_send commands with direct signatures and gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"4\",\"digest\":\"0x5555555555555555555555555555555555555555555555555555555555555555\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct {
        object: usize = 0,
        unsafe: usize = 0,
        execute: usize = 0,
        params_text: ?[]const u8 = null,
    };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x6666666666666666666666666666666666666666666666666666666666666666\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                state.execute += 1;
                state.params_text = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expectEqual(@as(usize, 1), counts.execute);

    const captured = counts.params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expect(params.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", params.value.array.items[1].array.items[0].string);
}

test "runCommand tx_payload move-call with selected arguments and gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0x123\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",7]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x7777777777777777777777777777777777777777777777777777777777777777\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { owned: usize = 0, normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                state.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x8888888888888888888888888888888888888888888888888888888888888888\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 1), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_send commands with selected arguments and gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0x123\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\"],\"address\":\"0xdef\"}]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"4\",\"digest\":\"0x9999999999999999999999999999999999999999999999999999999999999999\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct {
        owned: usize = 0,
        object: usize = 0,
        unsafe: usize = 0,
        execute: usize = 0,
        params_text: ?[]const u8 = null,
    };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getOwnedObjects")) {
                state.owned += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xabc\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0x123\"}}}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xabc") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                state.execute += 1;
                state.params_text = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.owned);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expectEqual(@as(usize, 1), counts.execute);

    const captured = counts.params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expect(params.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", params.value.array.items[1].array.items[0].string);
}

test "runCommand tx_payload rejects incomplete move-call context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_confirm waits for transaction result" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_confirm,
        .has_command = true,
        .tx_digest = "0xabc",
        .confirm_poll_ms = 1,
        .confirm_timeout_ms = 5000,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_request = false;
    var call_count: usize = 0;
    const MockContext = struct {
        saw_request: *bool,
        call_count: *usize,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.call_count.* += 1;

            if (ctx.call_count.* == 1) {
                return alloc.dupe(u8, "{\"result\":null}");
            }
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\",\"effects\":{\"status\":\"success\"}}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_request = &saw_request,
        .call_count = &call_count,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_request);
    try testing.expectEqual(@as(usize, 2), call_count);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\",\"effects\":{\"status\":\"success\"}}}\n", output.items);
}

test "runCommand tx_send with commands sends execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_options = "{\"skipChecks\":true}",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var unsafe_batch_calls: usize = 0;
    var saw_request = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        unsafe_batch_calls: *usize,
        saw_request: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe_batch_calls.* += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.saw_request.* = true;
                ctx.params_text.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var mock_ctx = MockContext{
        .unsafe_batch_calls = &unsafe_batch_calls,
        .saw_request = &saw_request,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), unsafe_batch_calls);
    try testing.expect(saw_request);
    try testing.expectEqualStrings("{\"result\":{\"executed\":true}}\n", output.items);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 3), params.value.array.items.len);

    try testing.expectEqualStrings("AQIDBA==", params.value.array.items[0].string);
    try testing.expect(params.value.array.items[1] == .array);
    const signatures = params.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
    try testing.expect(params.value.array.items[2] == .object);
    try testing.expect(params.value.array.items[2].object.get("skipChecks") != null);
}

test "runCommand tx_send move-call sends execute payload" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var unsafe_move_calls: usize = 0;
    var saw_request = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        unsafe_move_calls: *usize,
        saw_request: *bool,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                ctx.unsafe_move_calls.* += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.saw_request.* = true;
                ctx.params_text.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var mock_ctx = MockContext{
        .unsafe_move_calls = &unsafe_move_calls,
        .saw_request = &saw_request,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), unsafe_move_calls);
    try testing.expect(saw_request);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqualStrings("AQIDBA==", params.value.array.items[0].string);
    const signatures = params.value.array.items[1].array;
    try testing.expectEqual(@as(usize, 1), signatures.items.len);
    try testing.expectEqualStrings("sig-a", signatures.items[0].string);
}

test "runCommand tx_send move-call with from-keystore uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seed = [_]u8{0x35} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = 0;
    encoded_key_bytes[1..].* = seed;
    const encoded_len = std.base64.standard.Encoder.calcSize(encoded_key_bytes.len);
    const encoded_key = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_key);
    _ = std.base64.standard.Encoder.encode(encoded_key, &encoded_key_bytes);

    const keystore_contents = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{encoded_key});
    defer allocator.free(keystore_contents);
    const expected_sender = try client.keystore.resolveAddressFromKeystoreContents(
        allocator,
        keystore_contents,
        encoded_key,
    ) orelse return error.TestUnexpectedResult;
    defer allocator.free(expected_sender);

    const cwd = std.fs.cwd();
    const keystore_path = "tmp_unsafe_move_call_send_keystore.json";
    try cwd.writeFile(.{
        .sub_path = keystore_path,
        .data = keystore_contents,
    });
    defer cwd.deleteFile(keystore_path) catch {};

    const old_override = client.keystore.test_keystore_path_override;
    client.keystore.test_keystore_path_override = keystore_path;
    defer client.keystore.test_keystore_path_override = old_override;

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0x1111111111111111111111111111111111111111111111111111111111111111\"]",
        .tx_build_gas_budget = 800,
        .tx_build_gas_payment = "[{\"objectId\":\"0x9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"2\",\"digest\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        .from_keystore = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct {
        gas_price: usize = 0,
        normalized: usize = 0,
        object: usize = 0,
        unsafe_calls: usize = 0,
        execute_calls: usize = 0,
        expected_sender: []const u8,
    };
    var state = State{
        .expected_sender = expected_sender,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const ctx = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                ctx.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"8\"}");
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.object += 1;
                std.debug.assert(std.mem.indexOf(u8, req.params_json, "0x1111111111111111111111111111111111111111111111111111111111111111") != null);
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"5\",\"digest\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"owner\":{\"AddressOwner\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                ctx.unsafe_calls += 1;
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_calls += 1;
                const params = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer params.deinit();
                std.debug.assert(params.value.array.items[0].string.len > 0);
                const signature = params.value.array.items[1].array.items[0].string;
                const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(signature) catch return error.OutOfMemory;
                std.debug.assert(decoded_len == 97);
                return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 1), state.normalized);
    try testing.expectEqual(@as(usize, 1), state.object);
    try testing.expectEqual(@as(usize, 0), state.unsafe_calls);
    try testing.expectEqual(@as(usize, 1), state.execute_calls);
    try testing.expectEqualStrings("{\"result\":{\"executed\":true}}\n", output.items);
}

test "runCommand tx_send rejects incomplete move-call context" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_sender = "0xabc",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_send with --wait confirms transaction" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_send_wait = true,
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var saw_unsafe_request = false;
    var saw_execute_request = false;
    var saw_confirm_request = false;

    const MockContext = struct {
        saw_unsafe_request: *bool,
        saw_execute_request: *bool,
        saw_confirm_request: *bool,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                ctx.saw_unsafe_request.* = true;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.saw_execute_request.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.saw_confirm_request.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var mock_ctx = MockContext{
        .saw_unsafe_request = &saw_unsafe_request,
        .saw_execute_request = &saw_execute_request,
        .saw_confirm_request = &saw_confirm_request,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(saw_unsafe_request);
    try testing.expect(saw_execute_request);
    try testing.expect(saw_confirm_request);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}\n", output.items);
}

test "runCommand tx_send with commands and --summarize prints structured summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_send_summarize = true,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_executeTransactionBlock"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"digest\":\"0xsum\",\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"5\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[{\"owner\":{\"AddressOwner\":\"0xabc\"},\"coinType\":\"0x2::sui::SUI\",\"amount\":\"-6\"}]}}",
            );
        }
    }.call;

    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("success", parsed.value.object.get("status").?.string);
    try testing.expect(parsed.value.object.get("gas_summary") != null);
    try testing.expect(parsed.value.object.get("balance_changes") != null);
}

test "runCommand tx_send tx-bytes with --observe prints confirmed observation summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_bytes = "AAAA",
        .tx_send_observe = true,
        .confirm_timeout_ms = 5000,
        .confirm_poll_ms = 1,
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var request_count: usize = 0;

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const count = @as(*usize, @ptrCast(@alignCast(context)));
            count.* += 1;

            if (count.* == 1) {
                std.debug.assert(std.mem.eql(u8, req.method, "sui_executeTransactionBlock"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xobs\"}}");
            }

            std.debug.assert(std.mem.eql(u8, req.method, "sui_getTransactionBlock"));
            std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0xobs\",{\"showEffects\":true,\"showBalanceChanges\":true}]"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"digest\":\"0xobs\",\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"8\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[{\"owner\":{\"AddressOwner\":\"0xsender\"},\"coinType\":\"0x2::sui::SUI\",\"amount\":\"-9\"}]}}",
            );
        }
    }.call;

    rpc.request_sender = .{
        .context = &request_count,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 2), request_count);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("0xobs", parsed.value.object.get("digest").?.string);
    try testing.expect(parsed.value.object.get("confirmed_response") != null);
    try testing.expect(parsed.value.object.get("insights") != null);
}

test "runCommand tx_simulate with --summarize prints structured inspect summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"events\":[{\"type\":\"A\"}],\"results\":[{\"returnValues\":[]},{\"returnValues\":[]}]}}",
            );
        }
    }.call;

    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("success", parsed.value.object.get("status").?.string);
    try testing.expectEqual(@as(i64, 2), parsed.value.object.get("results_count").?.integer);
    try testing.expectEqual(@as(i64, 1), parsed.value.object.get("events_count").?.integer);
}

test "runCommand tx_dry_run tx-bytes sends dry-run request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var method_ok = false;
    var params_ok = false;

    const MockContext = struct {
        method_ok: *bool,
        params_ok: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock");
            ctx.params_ok.* = std.mem.eql(u8, req.params_json, "[\"AAAA\"]");
            return alloc.dupe(
                u8,
                "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_bytes = "AAAA",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_ok = &params_ok,
    };
    rpc.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expect(method_ok);
    try testing.expect(params_ok);
}

test "runCommand tx_dry_run with --summarize prints structured execution summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"5\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[{\"owner\":{\"AddressOwner\":\"0xabc\"},\"coinType\":\"0x2::sui::SUI\",\"amount\":\"-6\"}]}}",
            );
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_bytes = "AAAA",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("success", parsed.value.object.get("status").?.string);
    try testing.expect(parsed.value.object.get("gas_summary") != null);
    try testing.expect(parsed.value.object.get("balance_changes") != null);
}

test "runCommand tx_dry_run move-call with explicit gas metadata uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[7]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_dry_run request artifact uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0x123\",\"gasBudget\":1200,\"gasPrice\":8,\"gasPayment\":[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}],\"summarize\":true}",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_dry_run request artifact with auto gas budget estimates before final dry run" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return switch (state.dry_run) {
                    1 => alloc.dupe(
                        u8,
                        "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"10\",\"storageCost\":\"4\",\"storageRebate\":\"1\"}},\"balanceChanges\":[]}}",
                    ),
                    else => alloc.dupe(
                        u8,
                        "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"11\",\"storageCost\":\"3\",\"storageRebate\":\"1\"}},\"balanceChanges\":[]}}",
                    ),
                };
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--request",
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0x123\",\"gasBudget\":1200,\"gasPrice\":8,\"gasPayment\":[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}],\"autoGasBudget\":true,\"summarize\":true}",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 2), counts.normalized);
    try testing.expectEqual(@as(usize, 2), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_dry_run request artifact from stdin uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const old_override = cli.test_stdin_value_override;
    defer cli.test_stdin_value_override = old_override;
    cli.test_stdin_value_override =
        "{\"commands\":[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[7]}],\"sender\":\"0x123\",\"gasBudget\":1200,\"gasPrice\":8,\"gasPayment\":[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}],\"summarize\":true}";

    const Counts = struct {
        normalized: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = try cli.parseCliArgs(allocator, &.{
        "tx",
        "dry-run",
        "--request",
        "@-",
    });
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_dry_run auto-lowers vector object args without unsafe fallback" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        objects: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.objects += 1;
                return if (std.mem.indexOf(u8, req.params_json, "\"0x1111111111111111111111111111111111111111111111111111111111111111\"") != null)
                    alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"7\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                    )
                else
                    alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"8\",\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                    );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "router",
        .tx_build_function = "submit_coins",
        .tx_build_type_args = "[]",
        .tx_build_args = "[[\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"0x2222222222222222222222222222222222222222222222222222222222222222\"]]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 2), counts.objects);
    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_dry_run auto-lowers common pure wrapper args without unsafe fallback" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        objects: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x1\",\"module\":\"string\",\"name\":\"String\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x2\",\"module\":\"object\",\"name\":\"ID\",\"typeParams\":[]}},{\"Struct\":{\"address\":\"0x1\",\"module\":\"option\",\"name\":\"Option\",\"typeParams\":[\"U64\"]}},{\"Struct\":{\"address\":\"0x1\",\"module\":\"ascii\",\"name\":\"String\",\"typeParams\":[]}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.objects += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xshould-not-be-used\",\"version\":\"1\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "pure_helpers",
        .tx_build_function = "submit",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"hello\",\"0x1111111111111111111111111111111111111111111111111111111111111111\",7,\"ASCII\"]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 0), counts.objects);
    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_dry_run substitutes concrete struct type args for generic object vectors without unsafe fallback" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Counts = struct {
        normalized: usize = 0,
        objects: usize = 0,
        dry_run: usize = 0,
        unsafe: usize = 0,
    };
    var counts = Counts{};

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Vector\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"coin\",\"name\":\"Coin\",\"typeParams\":[{\"TypeParameter\":0}]}}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\",\"typeParams\":[]}}}],\"typeParameters\":[{\"constraints\":[]}],\"return\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.objects += 1;
                return if (std.mem.indexOf(u8, req.params_json, "\"0x1111111111111111111111111111111111111111111111111111111111111111\"") != null)
                    alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"7\",\"digest\":\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                    )
                else
                    alloc.dupe(
                        u8,
                        "{\"result\":{\"data\":{\"objectId\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"8\",\"digest\":\"0x2222222222222222222222222222222222222222222222222222222222222222\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                    );
            }
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "router",
        .tx_build_function = "submit_generic_coins",
        .tx_build_type_args = "[\"0x2::sui::SUI\"]",
        .tx_build_args = "[[\"0x1111111111111111111111111111111111111111111111111111111111111111\",\"0x2222222222222222222222222222222222222222222222222222222222222222\"]]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 2), counts.objects);
    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_status with --summarize prints structured summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_status,
        .has_command = true,
        .tx_digest = "0xstatus",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getTransactionBlock"));
            std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0xstatus\",{\"showEffects\":true,\"showBalanceChanges\":true}]"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"digest\":\"0xstatus\",\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"6\",\"storageCost\":\"2\",\"storageRebate\":\"1\"}},\"balanceChanges\":[{\"owner\":{\"AddressOwner\":\"0xreader\"},\"coinType\":\"0x2::sui::SUI\",\"amount\":\"-7\"}]}}",
            );
        }
    }.call;

    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("success", parsed.value.object.get("status").?.string);
    try testing.expect(parsed.value.object.get("gas_summary") != null);
    try testing.expect(parsed.value.object.get("balance_changes") != null);
}

test "runCommand tx_confirm with --observe prints observed confirmation summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_confirm,
        .has_command = true,
        .tx_digest = "0xconfirm",
        .tx_send_observe = true,
        .confirm_timeout_ms = 5000,
        .confirm_poll_ms = 1,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getTransactionBlock"));
            std.debug.assert(std.mem.eql(u8, req.params_json, "[\"0xconfirm\",{\"showEffects\":true,\"showBalanceChanges\":true}]"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"digest\":\"0xconfirm\",\"effects\":{\"status\":{\"status\":\"success\"},\"gasUsed\":{\"computationCost\":\"9\",\"storageCost\":\"3\",\"storageRebate\":\"1\"}},\"balanceChanges\":[{\"owner\":{\"AddressOwner\":\"0xconfirmer\"},\"coinType\":\"0x2::sui::SUI\",\"amount\":\"-11\"}]}}",
            );
        }
    }.call;

    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("0xconfirm", parsed.value.object.get("digest").?.string);
    try testing.expect(parsed.value.object.get("confirmed_response") != null);
    try testing.expect(parsed.value.object.get("insights") != null);
}

test "runCommand tx_send rejects tx-bytes with programmable inputs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_bytes = "dGVzdF90eF9ieXRlcw==",
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_send rejects empty tx_send payload input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
    };
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_payload rejects empty payload input" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
    };
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_payload rejects tx-bytes with programmable inputs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_bytes = "dGVzdF90eF9ieXRlcw==",
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(allocator, &rpc, &args, output.writer(allocator)));
}

test "runCommand tx_build move-call prints instruction JSON" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "[\"0xabc\",1]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const kind = parsed.value.object.get("kind").?;
    try testing.expect(kind == .string);
    try testing.expectEqualStrings("MoveCall", kind.string);
    const package_id = parsed.value.object.get("package").?;
    try testing.expect(package_id == .string);
    try testing.expectEqualStrings("0x2", package_id.string);
    const module = parsed.value.object.get("module").?;
    try testing.expect(module == .string);
    try testing.expectEqualStrings("counter", module.string);
    const function_name = parsed.value.object.get("function").?;
    try testing.expect(function_name == .string);
    try testing.expectEqualStrings("increment", function_name.string);
    const type_arguments = parsed.value.object.get("typeArguments").?;
    try testing.expect(type_arguments == .array);
    try testing.expect(type_arguments.array.items.len == 1);
    const call_args = parsed.value.object.get("arguments").?;
    try testing.expect(call_args == .array);
    try testing.expect(call_args.array.items.len == 2);
}

test "runCommand tx_build move-call with --summarize prints instruction summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "[\"0xabc\",1]",
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("instruction", parsed.value.object.get("artifact_kind").?.string);
    try testing.expectEqualStrings("MoveCall", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0x2", parsed.value.object.get("package").?.string);
    try testing.expectEqualStrings("counter", parsed.value.object.get("module").?.string);
    try testing.expectEqualStrings("increment", parsed.value.object.get("function_name").?.string);
    try testing.expectEqual(@as(i64, 1), parsed.value.object.get("type_arguments_count").?.integer);
    try testing.expectEqual(@as(i64, 2), parsed.value.object.get("arguments_count").?.integer);
}

test "runCommand tx_build move-call with emit-tx-block includes gas metadata" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const kind = parsed.value.object.get("kind").?;
    try testing.expectEqualStrings("ProgrammableTransaction", kind.string);
    try testing.expect(parsed.value.object.get("sender").? == .string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expect(parsed.value.object.get("gasBudget").? == .integer);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gasBudget").?.integer);
    try testing.expect(parsed.value.object.get("gasPrice").? == .integer);
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("gasPrice").?.integer);
    const commands = parsed.value.object.get("commands").?;
    try testing.expect(commands == .array);
    try testing.expect(commands.array.items.len == 1);
    const instruction = commands.array.items[0];
    try testing.expect(instruction == .object);
    try testing.expectEqualStrings("MoveCall", instruction.object.get("kind").?.string);
}

test "runCommand tx_build move-call resolves selected argument tokens into instruction output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\"]",
        .tx_build_sender = "0xsender",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xdef456\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"MoveCall\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xdef456") != null);
}

test "runCommand tx_build move-call resolves ownerless selected tokens from explicit sibling owner" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\",\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\"]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var request_count: usize = 0;
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const count = @as(*usize, @ptrCast(@alignCast(context)));
            count.* += 1;
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xowner") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xcafe01\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;
    rpc.request_sender = .{
        .context = &request_count,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqual(@as(usize, 2), request_count);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xcafe01") != null);
}

test "runCommand tx_build move-call resolves object-input selected tokens into move-call output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "pool",
        .tx_build_function = "swap",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0xshared\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"mutable\\\":true}\"]",
        .tx_build_sender = "0xsender",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xshared") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xshared\",\"version\":\"9\",\"digest\":\"shared-digest\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"4\"}}}}}",
            );
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"SharedObject\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"mutable\":true") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xshared") != null);
}

test "runCommand tx_build move-call resolves object-input inline metadata without object lookup" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "clocked",
        .tx_build_function = "touch",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"object_input\\\",\\\"objectId\\\":\\\"0x6\\\",\\\"inputKind\\\":\\\"shared\\\",\\\"initialSharedVersion\\\":1}\"]",
        .tx_build_sender = "0xsender",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: RpcRequest) ![]u8 {
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"SharedObject\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"objectId\":\"0x6\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"initialSharedVersion\":1") != null);
}

test "runCommand tx_build move-call resolves object preset tokens without object lookup" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "clocked",
        .tx_build_function = "touch",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"clock\\\"}\"]",
        .tx_build_sender = "0xsender",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: RpcRequest) ![]u8 {
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"SharedObject\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"objectId\":\"0x6\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"initialSharedVersion\":1") != null);
}

test "runCommand tx_build move-call resolves cetus object preset tokens into move-call output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = client.package_preset.cetus_clmm_mainnet,
        .tx_build_module = "pool",
        .tx_build_function = "swap",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"select:{\\\"kind\\\":\\\"object_preset\\\",\\\"name\\\":\\\"cetus_clmm_global_config_mainnet\\\"}\"]",
        .tx_build_sender = "0xsender",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "sui_getObject"));
            std.debug.assert(std.mem.indexOf(u8, req.params_json, "0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f") != null);
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":{\"objectId\":\"0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f\",\"version\":\"11\",\"digest\":\"cetus-config-digest\",\"owner\":{\"Shared\":{\"initial_shared_version\":\"7\"}}}}}",
            );
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"SharedObject\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"objectId\":\"0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"initialSharedVersion\":7") != null);
}

test "runCommand tx_build move-call resolves package aliases into move-call output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = client.package_preset.cetus_clmm_mainnet,
        .tx_build_module = "pool",
        .tx_build_function = "swap",
        .tx_build_type_args = "[]",
        .tx_build_args = "[7]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, client.package_preset.cetus_clmm_mainnet) != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"module\":\"pool\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"function\":\"swap\"") != null);
}

test "runCommand tx_build programmable resolves raw command package aliases into tx-block output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const argv = [_][]const u8{
        "tx",
        "build",
        "programmable",
        "--commands",
        "[{\"kind\":\"MoveCall\",\"package\":\"cetus_clmm_mainnet\",\"module\":\"pool\",\"function\":\"swap\",\"typeArguments\":[],\"arguments\":[7]}]",
        "--sender",
        "0xsender",
        "--gas-budget",
        "1000",
        "--gas-price",
        "7",
    };
    var args = try cli.parseCliArgs(allocator, &argv);
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, client.package_preset.cetus_clmm_mainnet) != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"kind\":\"MoveCall\"") != null);
}

test "runCommand tx_build programmable resolves selected argument tokens into tx-block output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"select:{\\\"kind\\\":\\\"owned_object_struct_type\\\",\\\"owner\\\":\\\"0xowner\\\",\\\"structType\\\":\\\"0x2::example::Thing\\\"}\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            std.debug.assert(std.mem.eql(u8, req.method, "suix_getOwnedObjects"));
            return alloc.dupe(
                u8,
                "{\"result\":{\"data\":[{\"data\":{\"objectId\":\"0xfedcba\",\"type\":\"0x2::example::Thing\",\"owner\":{\"AddressOwner\":\"0xowner\"}}}],\"hasNextPage\":false}}",
            );
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"ProgrammableTransaction\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xfedcba") != null);
}

test "runCommand tx_build programmable resolves selected gas payment tokens into tx-block output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_emit_tx_block = true,
        .tx_build_gas_payment = "select:{\"kind\":\"gas_coin\",\"minBalance\":10}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(_: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            if (std.mem.eql(u8, req.method, "suix_getCoins")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":[{\"coinType\":\"0x2::sui::SUI\",\"coinObjectId\":\"0xgas-build\",\"version\":\"21\",\"digest\":\"digest-gas-build\",\"balance\":\"99\"}],\"hasNextPage\":false}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0xabc\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                return alloc.dupe(u8, "{\"result\":\"7\"}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expect(std.mem.indexOf(u8, output.items, "\"ProgrammableTransaction\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"inputs\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"gasPayment\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "0xgas-build") != null);
}

test "runCommand tx_dry_run raw make-move-vec with struct type uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_dry_run,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MakeMoveVec\",\"type\":\"0x1::string::String\",\"elements\":[\"hello\",\"world\"]}]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_send_summarize = true,
    };

    const Counts = struct { dry_run: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_dryRunTransactionBlock")) {
                state.dry_run += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"effects\":{\"status\":{\"status\":\"success\"}},\"balanceChanges\":[]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;

    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 1), counts.dry_run);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
}

test "runCommand tx_build move-call with emit-tx-block and explicit gas payment uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { normalized: usize = 0, object: usize = 0, unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                state.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                state.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(parsed.value.object.get("inputs") != null);
    try testing.expect(parsed.value.object.get("gasData") != null);
    try testing.expect(parsed.value.object.get("commands") != null);
}

test "runCommand tx_simulate move-call with explicit gas payment uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\",7]",
        .tx_build_sender = "0x123",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { normalized: usize = 0, object: usize = 0, inspect: usize = 0 };
    var counts = Counts{};
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        counts: *Counts,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_getNormalizedMoveFunction")) {
                ctx.counts.normalized += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"parameters\":[{\"Struct\":{\"address\":\"0x2\",\"module\":\"counter\",\"name\":\"Counter\"}},\"U64\",{\"MutableReference\":{\"Struct\":{\"address\":\"0x2\",\"module\":\"tx_context\",\"name\":\"TxContext\"}}}]}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_getObject")) {
                ctx.counts.object += 1;
                return alloc.dupe(
                    u8,
                    "{\"result\":{\"data\":{\"objectId\":\"0xabc\",\"version\":\"9\",\"digest\":\"0x4444444444444444444444444444444444444444444444444444444444444444\",\"owner\":{\"AddressOwner\":\"0x123\"}}}}",
                );
            }
            if (std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock")) {
                ctx.counts.inspect += 1;
                ctx.params_text.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{
        .counts = &counts,
        .params_text = &params_text,
    };
    rpc.request_sender = .{
        .context = &mock_ctx,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}\n", output.items);
    try testing.expectEqual(@as(usize, 1), counts.normalized);
    try testing.expectEqual(@as(usize, 1), counts.object);
    try testing.expectEqual(@as(usize, 1), counts.inspect);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expect(tx_block.value.object.get("inputs") != null);
    try testing.expect(tx_block.value.object.get("gasData") != null);
}

test "runCommand tx_build programmable outputs transaction block" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gasBudget").?.integer);
    const commands = parsed.value.object.get("commands").?;
    try testing.expect(commands == .array);
    try testing.expectEqual(@as(usize, 1), commands.array.items.len);
    const instruction = commands.array.items[0];
    try testing.expectEqualStrings("MoveCall", instruction.object.get("kind").?.string);
}

test "runCommand tx_build programmable lowers typed make-move-vec pure elements into local transaction blocks" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MakeMoveVec\",\"type\":\"address\",\"elements\":[\"0x111\",\"0x222\"]},{\"kind\":\"MakeMoveVec\",\"type\":\"u64\",\"elements\":[7,8]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value.object.get("inputs") != null);
    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("MakeMoveVec", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("address", commands.items[0].object.get("type").?.string);
    try testing.expectEqualStrings("u64", commands.items[1].object.get("type").?.string);
}

test "runCommand tx_build programmable with --summarize prints transaction block summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_send_summarize = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("transaction_block", parsed.value.object.get("artifact_kind").?.string);
    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gas_budget").?.integer);
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("gas_price").?.integer);
    try testing.expectEqual(@as(i64, 1), parsed.value.object.get("command_count").?.integer);
}

test "runCommand tx_build programmable rejects invalid command json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "{\"kind\":\"\"}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_build programmable accepts single command object and repeatable command items" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
    };
    defer args.deinit(allocator);
    try args.tx_build_command_items.append(allocator, "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}");
    try args.tx_build_command_items.append(allocator, "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"],\"address\":\"0xdef\"}]");

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xabc", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 1000), parsed.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("gasPrice").?.integer);

    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", commands.items[1].object.get("kind").?.string);
}

test "runCommand tx_build programmable accepts single command object" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1200,
        .tx_build_gas_price = 8,
    };
    defer args.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 1), commands.items.len);
    try testing.expectEqualStrings("MoveCall", commands.items[0].object.get("kind").?.string);
}

test "runCommand tx_build move-call rejects command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_build programmable rejects move-call fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "runCommand tx_build rejects invalid move-call array arguments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[\"T\"]",
        .tx_build_args = "\"not-an-array\"",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try testing.expectError(error.InvalidCli, runCommand(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
    ));
}

test "printResponse supports pretty and compact modes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const response = "{\"result\":{\"tx\":\"abc\"},\"jsonrpc\":\"2.0\"}";

    var compact = std.ArrayList(u8){};
    defer compact.deinit(allocator);
    const compact_writer = compact.writer(allocator);
    try printResponse(allocator, compact_writer, response, false);
    try testing.expectEqualStrings("{\"result\":{\"tx\":\"abc\"},\"jsonrpc\":\"2.0\"}\n", compact.items);

    var pretty = std.ArrayList(u8){};
    defer pretty.deinit(allocator);
    const pretty_writer = pretty.writer(allocator);
    try printResponse(allocator, pretty_writer, response, true);

    const pretty_json = try std.json.parseFromSlice(std.json.Value, allocator, pretty.items, .{});
    defer pretty_json.deinit();

    try testing.expect(pretty_json.value == .object);
    try testing.expectEqualStrings("2.0", pretty_json.value.object.get("jsonrpc").?.string);
    try testing.expectEqualStrings("abc", pretty_json.value.object.get("result").?.object.get("tx").?.string);
    try testing.expect(std.mem.endsWith(u8, pretty.items, "\n"));
}

test "runCommand tx_build programmable lowers publish and upgrade into local transaction blocks" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value.object.get("inputs") != null);
    try testing.expect(parsed.value.object.get("gasData") != null);
    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("Publish", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", commands.items[1].object.get("kind").?.string);
}

test "runCommand tx_simulate programmable lowers publish and upgrade into local inspect payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct {
        inspect: usize = 0,
        params_text: ?[]const u8 = null,
    };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock")) {
                state.inspect += 1;
                state.params_text = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}\n", output.items);
    try testing.expectEqual(@as(usize, 1), counts.inspect);

    const captured = counts.params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expect(tx_block.value.object.get("inputs") != null);
    try testing.expect(tx_block.value.object.get("gasData") != null);
    const commands = tx_block.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("Publish", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", commands.items[1].object.get("kind").?.string);
}

test "runCommand tx_payload programmable publish and upgrade with direct signatures use local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { unsafe: usize = 0 };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", payload.value.array.items[1].array.items[0].string);
}

test "runCommand tx_send programmable publish and upgrade with direct signatures uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };
    try args.signatures.append(allocator, "sig-a");
    defer args.signatures.deinit(allocator);

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct {
        unsafe: usize = 0,
        execute: usize = 0,
        params_text: ?[]const u8 = null,
    };
    var counts = Counts{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const state = @as(*Counts, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) {
                state.unsafe += 1;
                return alloc.dupe(u8, "{\"result\":{\"txBytes\":\"AQIDBA==\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                state.execute += 1;
                state.params_text = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"executed\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &counts,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try runCommand(allocator, &rpc, &args, output.writer(allocator));

    try testing.expectEqual(@as(usize, 0), counts.unsafe);
    try testing.expectEqual(@as(usize, 1), counts.execute);

    const captured = counts.params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expect(params.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-a", params.value.array.items[1].array.items[0].string);
}

test "runCommandWithProgrammaticProvider tx_build programmable publish and upgrade use local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .has_command = true,
        .tx_build_kind = .programmable,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_build_emit_tx_block = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "build-provider-publish-upgrade" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-build-provider-publish-upgrade",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0x123", parsed.value.object.get("sender").?.string);
    try testing.expect(parsed.value.object.get("inputs") != null);
    try testing.expect(parsed.value.object.get("gasData") != null);
    const commands = parsed.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("Publish", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", commands.items[1].object.get("kind").?.string);
}

test "runCommandWithProgrammaticProvider tx_simulate programmable publish and upgrade use local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_simulate,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const Counts = struct { inspect: usize = 0 };
    var counts = Counts{};
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        counts: *Counts,
        params_text: *?[]const u8,
    };
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock")) {
                ctx.counts.inspect += 1;
                ctx.params_text.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    var mock_ctx = MockContext{ .counts = &counts, .params_text = &params_text };
    rpc.request_sender = .{ .context = &mock_ctx, .callback = callback };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "simulate-provider-publish-upgrade" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-simulate-provider-publish-upgrade",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}\n", output.items);
    try testing.expectEqual(@as(usize, 1), counts.inspect);

    const captured = params_text orelse return error.TestUnexpectedResult;
    defer allocator.free(captured);
    const params = try std.json.parseFromSlice(std.json.Value, allocator, captured, .{});
    defer params.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, params.value.array.items[0].string, .{});
    defer tx_block.deinit();
    try testing.expectEqualStrings("0x123", tx_block.value.object.get("sender").?.string);
    try testing.expect(tx_block.value.object.get("inputs") != null);
    try testing.expect(tx_block.value.object.get("gasData") != null);
    const commands = tx_block.value.object.get("commands").?.array;
    try testing.expectEqual(@as(usize, 2), commands.items.len);
    try testing.expectEqualStrings("Publish", commands.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", commands.items[1].object.get("kind").?.string);
}

test "runCommandWithProgrammaticProvider tx_send programmable publish and upgrade uses local programmable builder path" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct {
        execute: usize = 0,
    };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                std.debug.assert(std.mem.eql(u8, payload.value.array.items[1].array.items[0].string, "sig-provider-local-builder"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xprovider-local-builder\"}}");
            }
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .remote_signer = .{
                .address = "0x123",
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            return .{
                                .sender = "0x123",
                                .signatures = &.{"sig-provider-local-builder"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "provider-local-builder-session" },
                .session_supports_execute = true,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.execute);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xprovider-local-builder", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_send programmable publish and upgrade prints local builder challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { execute: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "local-builder-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-local-builder-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0x123\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_send programmable publish and upgrade applies local builder challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"local-builder-provider-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { execute: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                st.execute += 1;
                const payload = std.json.parseFromSlice(std.json.Value, alloc, req.params_json, .{}) catch return error.OutOfMemory;
                defer payload.deinit();
                std.debug.assert(payload.value.array.items[0].string.len > 0);
                std.debug.assert(std.mem.eql(u8, payload.value.array.items[1].array.items[0].string, "sig-local-builder-provider-approved"));
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xlocal-builder-provider-approved\"}}");
            }
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "local-builder-provider-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expectEqualStrings("local-builder-provider-approved", req.account_session.session_id.?);
                            return .{
                                .sender = "0x123",
                                .signatures = &.{"sig-local-builder-provider-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-local-builder-provider",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.execute);
    try testing.expectEqual(@as(usize, 0), state.unsafe);

    const response = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer response.deinit();
    try testing.expectEqualStrings("0xlocal-builder-provider-approved", response.value.object.get("result").?.object.get("digest").?.string);
}

test "runCommandWithProgrammaticProvider tx_payload programmable publish and upgrade prints local builder challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { execute: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "local-builder-payload-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-local-builder-payload",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0x123\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_payload programmable publish and upgrade with inferred gas price prints local builder challenge prompt" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { gas_price: usize = 0, execute: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "suix_getReferenceGasPrice")) {
                st.gas_price += 1;
                return alloc.dupe(u8, "{\"result\":\"7\"}");
            }
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "local-builder-payload-gas-price-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, _: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            return .{};
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-local-builder-payload-gas-price",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(!authorizer_called);
    try testing.expectEqual(@as(usize, 1), state.gas_price);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expectEqual(@as(usize, 0), state.unsafe);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"account_address\":\"0x123\"") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\"challenge\"") != null);
}

test "runCommandWithProgrammaticProvider tx_payload programmable publish and upgrade applies local builder challenge response" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .has_command = true,
        .tx_build_commands = "[{\"kind\":\"Publish\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"]},{\"kind\":\"Upgrade\",\"modules\":[\"BAUG\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":{\"Result\":0}}]",
        .tx_build_gas_budget = 1000,
        .tx_build_gas_price = 7,
        .tx_build_gas_payment = "[{\"objectId\":\"0x999\",\"version\":\"3\",\"digest\":\"0x3333333333333333333333333333333333333333333333333333333333333333\"}]",
        .tx_session_response = "{\"supportsExecute\":true,\"session\":{\"kind\":\"passkey\",\"sessionId\":\"local-builder-payload-approved\"}}",
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    const State = struct { execute: usize = 0, unsafe: usize = 0 };
    var state = State{};
    const callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RpcRequest) error{OutOfMemory}![]u8 {
            const st = @as(*State, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) st.execute += 1;
            if (std.mem.eql(u8, req.method, "unsafe_moveCall") or std.mem.eql(u8, req.method, "unsafe_batchTransaction")) st.unsafe += 1;
            return error.OutOfMemory;
        }
    }.call;
    rpc.request_sender = .{
        .context = &state,
        .callback = callback,
    };

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    var authorizer_called = false;
    try runCommandWithProgrammaticProvider(
        allocator,
        &rpc,
        &args,
        output.writer(allocator),
        .{
            .passkey = .{
                .address = "0x123",
                .session = .{ .kind = .passkey, .session_id = "local-builder-payload-session" },
                .authorizer = .{
                    .context = &authorizer_called,
                    .callback = struct {
                        fn call(context: *anyopaque, _: std.mem.Allocator, req: client.tx_request_builder.RemoteAuthorizationRequest) !client.tx_request_builder.RemoteAuthorizationResult {
                            const seen = @as(*bool, @ptrCast(@alignCast(context)));
                            seen.* = true;
                            try testing.expect(req.tx_bytes_base64 != null);
                            try testing.expectEqualStrings("local-builder-payload-approved", req.account_session.session_id.?);
                            return .{
                                .sender = "0x123",
                                .signatures = &.{"sig-local-builder-payload-approved"},
                                .session = req.account_session,
                            };
                        }
                    }.call,
                },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-local-builder-payload",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    try testing.expect(authorizer_called);
    try testing.expectEqual(@as(usize, 0), state.execute);
    try testing.expectEqual(@as(usize, 0), state.unsafe);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, output.items, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expect(payload.value.array.items[0].string.len > 0);
    try testing.expectEqualStrings("sig-local-builder-payload-approved", payload.value.array.items[1].array.items[0].string);
}
