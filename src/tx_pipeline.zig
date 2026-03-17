const std = @import("std");
const cli = @import("./cli.zig");
const sui = @import("sui_client_zig");
const keystore = sui.keystore;
const tx_builder = sui.tx_builder;
const tx_request_builder = sui.tx_request_builder;

pub const TxInspectPayload = []const u8;
pub const TxExecutePayload = []const u8;

pub fn commandSourceFromArgs(args: *const cli.ParsedArgs) tx_builder.CommandSource {
    return .{
        .command_items = args.tx_build_command_items.items,
        .commands_json = args.tx_build_commands,
        .move_call = if (args.tx_build_package != null and args.tx_build_module != null and args.tx_build_function != null)
            .{
                .package_id = args.tx_build_package.?,
                .module = args.tx_build_module.?,
                .function_name = args.tx_build_function.?,
                .type_args = args.tx_build_type_args,
                .arguments = args.tx_build_args,
            }
        else
            null,
    };
}

pub fn resolvedTxBuildSenderFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !?[]const u8 {
    if (args.tx_build_sender) |sender| {
        if (sender.len == 0) return null;
        if (std.mem.startsWith(u8, sender, "0x")) {
            return try allocator.dupe(u8, sender);
        }
        return try keystore.resolveAddressBySelector(allocator, sender) orelse error.InvalidCli;
    }

    if (args.signers.items.len == 0) return null;

    var has_resolver_input = false;
    for (args.signers.items) |selector| {
        if (selector.len == 0) continue;
        has_resolver_input = true;
        const resolved_sender = try keystore.resolveAddressBySelector(allocator, selector) orelse continue;
        return resolved_sender;
    }

    if (has_resolver_input) return error.InvalidCli;
    return null;
}

pub fn defaultTxBuildAccountProviderFromArgs(
    args: *const cli.ParsedArgs,
) ?tx_request_builder.AccountProvider {
    const needs_sender_resolution = if (args.tx_build_sender) |sender|
        sender.len > 0 and !std.mem.startsWith(u8, sender, "0x")
    else
        false;
    if (args.signers.items.len == 0 and !needs_sender_resolution) return null;
    return .{
        .default_keystore = .{
            .preparation = .{
                .signer_selectors = args.signers.items,
                .from_keystore = false,
                .infer_sender_from_signers = true,
            },
        },
    };
}

pub fn programmaticRequestOptionsFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) tx_request_builder.ProgrammaticRequestOptions {
    return tx_request_builder.optionsFromCommandSource(commandSourceFromArgs(args), .{
        .sender = args.tx_build_sender,
        .gas_budget = args.tx_build_gas_budget,
        .gas_price = args.tx_build_gas_price,
        .signatures = signatures,
        .options_json = args.tx_options,
        .wait_for_confirmation = args.tx_send_wait,
        .confirm_timeout_ms = args.confirm_timeout_ms orelse std.math.maxInt(u64),
        .confirm_poll_ms = args.confirm_poll_ms,
    });
}

pub fn buildTxBuildTransactionBlockFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) ![]u8 {
    if (defaultTxBuildAccountProviderFromArgs(args)) |provider| {
        return try tx_request_builder.buildAuthorizedArtifact(
            allocator,
            tx_request_builder.optionsFromCommandSource(commandSourceFromArgs(args), .{
                .sender = args.tx_build_sender,
                .gas_budget = args.tx_build_gas_budget,
                .gas_price = args.tx_build_gas_price,
            }),
            provider,
            .transaction_block,
        );
    }

    const sender = try resolvedTxBuildSenderFromArgs(allocator, args);
    defer if (sender) |value| allocator.free(value);

    return try tx_request_builder.buildArtifactFromCommandSource(
        allocator,
        commandSourceFromArgs(args),
        .{
            .sender = sender,
            .gas_budget = args.tx_build_gas_budget,
            .gas_price = args.tx_build_gas_price,
        },
        .transaction_block,
    );
}

pub fn buildTxBuildInstructionFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) ![]u8 {
    return try tx_request_builder.buildInstructionFromCommandSource(
        allocator,
        commandSourceFromArgs(args),
    );
}

pub fn programmaticRequestFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) tx_builder.ProgrammaticTxRequest {
    return tx_request_builder.requestFromOptions(programmaticRequestOptionsFromArgs(args, signatures));
}

pub fn defaultProgrammaticAccountProviderFromArgs(
    args: *const cli.ParsedArgs,
) ?tx_request_builder.AccountProvider {
    if (!cli.supportsProgrammableInput(args)) return null;
    const needs_sender_resolution = if (args.tx_build_sender) |sender|
        sender.len > 0 and !std.mem.startsWith(u8, sender, "0x")
    else
        false;
    if (args.signers.items.len == 0 and !args.from_keystore and !needs_sender_resolution) return null;
    return .{
        .default_keystore = .{
            .preparation = .{
                .signer_selectors = args.signers.items,
                .from_keystore = args.from_keystore,
                .infer_sender_from_signers = true,
            },
        },
    };
}

pub fn programmaticAuthorizationPlanFromArgs(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) tx_request_builder.AuthorizationPlan {
    return programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, null);
}

pub fn programmaticAuthorizationPlanFromArgsWithAccountProvider(
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?tx_request_builder.AccountProvider,
) tx_request_builder.AuthorizationPlan {
    const options = programmaticRequestOptionsFromArgs(args, if (provider != null) signatures else &.{});
    if (provider) |value| {
        return tx_request_builder.authorizationPlan(options, value);
    }
    if (signatures.len == 0) {
        return tx_request_builder.authorizationPlan(options, .none);
    }
    return tx_request_builder.authorizationPlan(options, .{
        .direct_signatures = .{
            .signatures = signatures,
        },
    });
}

pub fn buildProgrammaticArtifactFromArgsWithAccountProvider(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    provider: ?tx_request_builder.AccountProvider,
    kind: tx_request_builder.ProgrammaticArtifactKind,
) ![]u8 {
    if (cli.hasProgrammaticTxContext(args)) {
        try cli.validateProgrammaticTxInput(args);
    }
    if (!cli.supportsProgrammableInput(args)) return error.InvalidCli;
    return try programmaticAuthorizationPlanFromArgsWithAccountProvider(args, signatures, provider)
        .buildArtifact(allocator, kind);
}

pub fn buildProgrammaticArtifactFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    kind: tx_request_builder.ProgrammaticArtifactKind,
) ![]u8 {
    return try buildProgrammaticArtifactFromArgsWithAccountProvider(
        allocator,
        args,
        signatures,
        defaultProgrammaticAccountProviderFromArgs(args),
        kind,
    );
}

pub fn preparedRequestFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
) !tx_builder.PreparedProgrammaticTxRequest {
    if (cli.hasProgrammaticTxContext(args)) {
        try cli.validateProgrammaticTxInput(args);
    }
    if (!cli.supportsProgrammableInput(args)) return error.InvalidCli;
    return try tx_request_builder.prepareRequest(
        allocator,
        programmaticRequestOptionsFromArgs(args, signatures),
    );
}

pub fn buildInspectPayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
) !TxInspectPayload {
    if (cli.hasProgrammaticTxContext(args)) {
        try cli.validateProgrammaticTxInput(args);
    }
    if (cli.supportsProgrammableInput(args)) {
        return try buildProgrammaticArtifactFromArgs(allocator, args, &.{}, .inspect_payload);
    }

    return try allocator.dupe(u8, args.params orelse "[]");
}

pub fn buildExecutePayloadFromArgs(
    allocator: std.mem.Allocator,
    args: *const cli.ParsedArgs,
    signatures: []const []const u8,
    non_programmatic_default: ?[]const u8,
) !TxExecutePayload {
    if (cli.hasProgrammaticTxContext(args)) {
        try cli.validateProgrammaticTxInput(args);
    }
    if (cli.supportsProgrammableInput(args)) {
        if (args.tx_bytes != null) return error.InvalidCli;
        return try buildProgrammaticArtifactFromArgs(allocator, args, signatures, .execute_payload);
    }

    const tx_bytes = args.tx_bytes orelse non_programmatic_default orelse return error.InvalidCli;
    return try tx_builder.buildExecutePayload(allocator, tx_bytes, signatures, args.tx_options);
}

test "programmaticRequestFromArgs maps parsed transaction settings" {
    const testing = std.testing;

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
        .tx_options = "{\"showEffects\":true}",
        .tx_send_wait = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 25,
    };

    const request = programmaticRequestFromArgs(&args, &.{"sig-a"});
    try testing.expectEqualStrings("0xabc", request.sender.?);
    try testing.expectEqual(@as(u64, 800), request.gas_budget.?);
    try testing.expectEqual(@as(u64, 6), request.gas_price.?);
    try testing.expectEqualStrings("{\"showEffects\":true}", request.options_json.?);
    try testing.expect(request.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 5_000), request.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 25), request.confirm_poll_ms);
    try testing.expectEqualStrings("sig-a", request.signatures[0]);
    try testing.expect(request.source.move_call != null);
}

test "programmaticRequestOptionsFromArgs maps parsed transaction settings" {
    const testing = std.testing;

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
        .tx_options = "{\"showEffects\":true}",
        .tx_send_wait = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 25,
    };

    const options = programmaticRequestOptionsFromArgs(&args, &.{"sig-a"});
    try testing.expect(options.source.commands_json != null);
    try testing.expectEqualStrings("0xabc", options.sender.?);
    try testing.expectEqual(@as(u64, 800), options.gas_budget.?);
    try testing.expectEqual(@as(u64, 6), options.gas_price.?);
    try testing.expectEqualStrings("{\"showEffects\":true}", options.options_json.?);
    try testing.expect(options.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 5_000), options.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 25), options.confirm_poll_ms);
    try testing.expectEqualStrings("sig-a", options.signatures[0]);
}

test "programmaticAuthorizationPlanFromArgs lifts signatures into a direct-signature provider" {
    const testing = std.testing;

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 800,
        .tx_build_gas_price = 6,
    };

    const plan = programmaticAuthorizationPlanFromArgs(&args, &.{"sig-a"});
    try testing.expectEqualStrings("0xabc", plan.options.sender.?);
    try testing.expectEqual(@as(u64, 800), plan.options.gas_budget.?);
    try testing.expectEqual(@as(u64, 6), plan.options.gas_price.?);
    try testing.expectEqual(@as(usize, 0), plan.options.signatures.len);

    switch (plan.provider) {
        .direct_signatures => |account| {
            try testing.expectEqualStrings("sig-a", account.signatures[0]);
            try testing.expect(account.sender == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "defaultProgrammaticAccountProviderFromArgs builds default-keystore providers from signer flags" {
    const testing = std.testing;

    var args = cli.ParsedArgs{
        .command = .tx_send,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .from_keystore = true,
    };
    try args.signers.append(std.testing.allocator, "builder");
    defer args.signers.deinit(std.testing.allocator);

    const provider = defaultProgrammaticAccountProviderFromArgs(&args) orelse return error.TestUnexpectedResult;
    switch (provider) {
        .default_keystore => |account| {
            try testing.expect(account.preparation.from_keystore);
            try testing.expect(account.preparation.infer_sender_from_signers);
            try testing.expectEqual(@as(usize, 1), account.preparation.signer_selectors.len);
            try testing.expectEqualStrings("builder", account.preparation.signer_selectors[0]);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "defaultProgrammaticAccountProviderFromArgs resolves non-address sender aliases through keystore providers" {
    const testing = std.testing;

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_sender = "builder",
    };

    const provider = defaultProgrammaticAccountProviderFromArgs(&args) orelse return error.TestUnexpectedResult;
    switch (provider) {
        .default_keystore => |account| {
            try testing.expect(!account.preparation.from_keystore);
            try testing.expect(account.preparation.infer_sender_from_signers);
            try testing.expectEqual(@as(usize, 0), account.preparation.signer_selectors.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "resolvedTxBuildSenderFromArgs resolves signer selectors from the default keystore" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_tx_pipeline_keystore_sender_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var args = cli.ParsedArgs{
        .command = .tx_build,
    };
    defer args.deinit(allocator);
    try args.signers.append(allocator, "builder");

    const sender = try resolvedTxBuildSenderFromArgs(allocator, &args) orelse return error.TestUnexpectedResult;
    defer allocator.free(sender);
    try testing.expectEqualStrings("0xbuilder", sender);
}

test "buildTxBuildTransactionBlockFromArgs resolves sender aliases into tx-block output" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_tx_pipeline_tx_build_block_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
    };
    defer args.deinit(allocator);
    try args.signers.append(allocator, "builder");

    const tx_block = try buildTxBuildTransactionBlockFromArgs(allocator, &args);
    defer allocator.free(tx_block);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, tx_block, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .object);
    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xbuilder", parsed.value.object.get("sender").?.string);
}

test "defaultTxBuildAccountProviderFromArgs derives default-keystore providers for tx-build sender resolution" {
    const testing = std.testing;

    var args = cli.ParsedArgs{
        .command = .tx_build,
        .tx_build_sender = "builder",
    };
    defer args.deinit(std.testing.allocator);

    const provider = defaultTxBuildAccountProviderFromArgs(&args) orelse return error.TestUnexpectedResult;
    switch (provider) {
        .default_keystore => |account| {
            try testing.expect(!account.preparation.from_keystore);
            try testing.expect(account.preparation.infer_sender_from_signers);
            try testing.expectEqual(@as(usize, 0), account.preparation.signer_selectors.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "preparedRequestFromArgs resolves command items into a prepared request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        .tx_build_sender = "0xabc",
        .tx_build_gas_budget = 900,
    };

    var prepared = try preparedRequestFromArgs(allocator, &args, &.{"sig-a"});
    defer prepared.deinit(allocator);

    try testing.expect(prepared.request.source.commands_json != null);
    try testing.expectEqualStrings("0xabc", prepared.request.sender.?);
    try testing.expectEqualStrings("sig-a", prepared.request.signatures[0]);
}

test "buildExecutePayloadFromArgs builds programmatic payloads through prepared requests" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .tx_build_package = "0x2",
        .tx_build_module = "counter",
        .tx_build_function = "increment",
        .tx_build_type_args = "[]",
        .tx_build_args = "[\"0xabc\"]",
        .tx_build_sender = "0xabc",
    };

    const payload = try buildExecutePayloadFromArgs(allocator, &args, &.{"sig-a"}, null);
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
}

test "buildProgrammaticArtifactFromArgs resolves default-keystore sender and signatures" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_tx_pipeline_keystore_artifact_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var args = cli.ParsedArgs{
        .command = .tx_payload,
        .tx_build_commands = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        .tx_build_sender = "builder",
    };
    defer args.deinit(allocator);
    try args.signers.append(allocator, "builder");

    const payload = try buildProgrammaticArtifactFromArgs(allocator, &args, &.{}, .execute_payload);
    defer allocator.free(payload);

    try testing.expect(std.mem.indexOf(u8, payload, "0xbuilder") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "sig-builder") != null);
}
