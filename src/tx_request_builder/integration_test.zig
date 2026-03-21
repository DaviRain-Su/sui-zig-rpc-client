/// tx_request_builder/integration_test.zig - Integration tests
const std = @import("std");
const tx_request_builder = @import("root.zig");

const AuthorizationPlan = tx_request_builder.AuthorizationPlan;
const OwnedAuthorizationPlan = tx_request_builder.OwnedAuthorizationPlan;
const AccountProvider = tx_request_builder.AccountProvider;
const ProgrammaticRequestOptions = tx_request_builder.ProgrammaticRequestOptions;
const SessionChallengeResponse = tx_request_builder.SessionChallengeResponse;
const buildTransactionBlockFromCommandSource = tx_request_builder.buildTransactionBlockFromCommandSource;
const CommandRequestConfig = tx_request_builder.CommandRequestConfig;

/// Test end-to-end authorization flow
test "end-to-end authorization flow with direct signer" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create options
    const options = ProgrammaticRequestOptions{
        .gas_budget = 1000000,
        .execute = true,
    };

    // Create direct signature provider
    const provider = AccountProvider{
        .direct = .{
            .private_key = "secret_key",
            .address = "0x123",
            .key_scheme = "ed25519",
        },
    };

    // Create authorization plan
    const plan = tx_request_builder.authorizationPlan(options, provider);

    // Verify can execute
    try testing.expect(plan.canExecute());

    // No challenge needed for direct signer
    try testing.expect(plan.challengeRequest() == null);
}

/// Test authorization flow with future wallet
test "end-to-end authorization flow with future wallet" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create options
    const options = ProgrammaticRequestOptions{};

    // Create future wallet provider without session
    const provider = AccountProvider{
        .future_wallet = .{
            .id = try allocator.dupe(u8, "wallet_1"),
            .wallet_type = try allocator.dupe(u8, "passkey"),
            .session_challenge = null,
        },
    };
    defer provider.deinit(allocator);

    // Create authorization plan
    var owned_plan = try tx_request_builder.ownedAuthorizationPlan(allocator, options, provider);
    defer owned_plan.deinit(allocator);

    // Cannot execute without session
    try testing.expect(!owned_plan.plan().canExecute());

    // Apply challenge response
    const response = SessionChallengeResponse{
        .challenge = .{ .none = {} },
        .response_data = try allocator.dupe(u8, "signature"),
        .account_id = try allocator.dupe(u8, "wallet_1"),
    };
    defer response.deinit(allocator);

    try owned_plan.withChallengeResponse(allocator, response);

    // Now can execute
    try testing.expect(owned_plan.plan().canExecute());
}

/// Test transaction building from command source
test "build transaction from move_call command" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create command config
    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("package", .{ .string = "0x2" });
    try params.put("module", .{ .string = "sui" });
    try params.put("function", .{ .string = "transfer" });

    const config = CommandRequestConfig{
        .command_type = try allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = params },
    };
    defer config.deinit(allocator);

    // Build transaction block
    var block = try buildTransactionBlockFromCommandSource(allocator, config);
    defer block.deinit(allocator);

    // Verify block structure
    try testing.expectEqual(@as(usize, 1), block.instructions.len);
}

/// Test multiple account provider types
test "authorization with different provider types" {
    const testing = std.testing;

    // Direct provider
    const direct = AccountProvider{
        .direct = .{
            .private_key = "key",
            .address = "0x123",
            .key_scheme = "ed25519",
        },
    };
    const direct_plan = AuthorizationPlan{
        .options = .{},
        .provider = direct,
    };
    try testing.expect(direct_plan.canExecute());

    // Keystore contents provider
    const keystore = AccountProvider{
        .keystore_contents = .{
            .contents = "[]",
            .address = "0x456",
        },
    };
    const keystore_plan = AuthorizationPlan{
        .options = .{},
        .provider = keystore,
    };
    try testing.expect(keystore_plan.canExecute());

    // Default keystore provider
    const default_ks = AccountProvider{
        .default_keystore = .{
            .address = null,
            .keystore_path = null,
        },
    };
    const default_plan = AuthorizationPlan{
        .options = .{},
        .provider = default_ks,
    };
    try testing.expect(default_plan.canExecute());

    // Remote signer without callback
    const remote_no_cb = AccountProvider{
        .remote_signer = .{
            .signer_id = "signer",
            .authorize_callback = null,
        },
    };
    const remote_plan = AuthorizationPlan{
        .options = .{},
        .provider = remote_no_cb,
    };
    try testing.expect(!remote_plan.canExecute());
}

/// Test owned authorization plan memory management
test "owned authorization plan memory management" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create with owned strings
    const options = ProgrammaticRequestOptions{
        .alias = try allocator.dupe(u8, "test_alias"),
        .sender = try allocator.dupe(u8, "0x123"),
        .gas_budget = 1000000,
    };

    const provider = AccountProvider{
        .direct = .{
            .private_key = try allocator.dupe(u8, "key"),
            .address = try allocator.dupe(u8, "0x123"),
            .key_scheme = try allocator.dupe(u8, "ed25519"),
        },
    };

    var owned = try tx_request_builder.ownedAuthorizationPlan(allocator, options, provider);
    defer owned.deinit(allocator);

    // Verify data is preserved
    const plan = owned.plan();
    try testing.expectEqualStrings("test_alias", plan.options.alias.?);
    try testing.expectEqualStrings("0x123", plan.options.sender.?);
    try testing.expectEqual(@as(?u64, 1000000), plan.options.gas_budget);
}

/// Test error handling in transaction building
test "transaction building error handling" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Missing package
    var params1 = std.json.ObjectMap.init(allocator);
    defer params1.deinit();
    try params1.put("module", .{ .string = "sui" });
    try params1.put("function", .{ .string = "transfer" });

    const config1 = CommandRequestConfig{
        .command_type = try allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = params1 },
    };
    defer config1.deinit(allocator);

    const result1 = buildTransactionBlockFromCommandSource(allocator, config1);
    try testing.expectError(error.MissingPackage, result1);

    // Missing module
    var params2 = std.json.ObjectMap.init(allocator);
    defer params2.deinit();
    try params2.put("package", .{ .string = "0x2" });
    try params2.put("function", .{ .string = "transfer" });

    const config2 = CommandRequestConfig{
        .command_type = try allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = params2 },
    };
    defer config2.deinit(allocator);

    const result2 = buildTransactionBlockFromCommandSource(allocator, config2);
    try testing.expectError(error.MissingModule, result2);

    // Missing function
    var params3 = std.json.ObjectMap.init(allocator);
    defer params3.deinit();
    try params3.put("package", .{ .string = "0x2" });
    try params3.put("module", .{ .string = "sui" });

    const config3 = CommandRequestConfig{
        .command_type = try allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = params3 },
    };
    defer config3.deinit(allocator);

    const result3 = buildTransactionBlockFromCommandSource(allocator, config3);
    try testing.expectError(error.MissingFunction, result3);
}

/// Test complex move call with arguments
test "complex move call with arguments" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create command config with arguments
    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("package", .{ .string = "0x2" });
    try params.put("module", .{ .string = "coin" });
    try params.put("function", .{ .string = "transfer" });

    var args = std.json.Array.init(allocator);
    defer args.deinit();
    try args.append(.{ .integer = 0 }); // gas
    try args.append(.{ .string = "0x456" }); // recipient
    try params.put("arguments", .{ .array = args });

    var type_args = std.json.Array.init(allocator);
    defer type_args.deinit();
    try type_args.append(.{ .string = "0x2::sui::SUI" });
    try params.put("type_arguments", .{ .array = type_args });

    const config = CommandRequestConfig{
        .command_type = try allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = params },
    };
    defer config.deinit(allocator);

    // Build transaction block
    var block = try buildTransactionBlockFromCommandSource(allocator, config);
    defer block.deinit(allocator);

    // Verify instruction
    try testing.expectEqual(@as(usize, 1), block.instructions.len);
    const instruction = block.instructions[0];
    try testing.expectEqual(@as(usize, 2), instruction.arguments.len);
    try testing.expectEqual(@as(usize, 1), instruction.type_arguments.len);
}

/// Test authorization plan with options
test "authorization plan with various options" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create options with all fields
    const options = ProgrammaticRequestOptions{
        .alias = try allocator.dupe(u8, "my_tx"),
        .gas_budget = 5000000,
        .gas_price = 1000,
        .sender = try allocator.dupe(u8, "0xabc"),
        .execute = true,
        .simulate = false,
    };

    const provider = AccountProvider{
        .direct = .{
            .private_key = "key",
            .address = "0xabc",
            .key_scheme = "ed25519",
        },
    };

    const plan = tx_request_builder.authorizationPlan(options, provider);

    // Verify options are preserved
    try testing.expectEqualStrings("my_tx", plan.options.alias.?);
    try testing.expectEqual(@as(?u64, 5000000), plan.options.gas_budget);
    try testing.expectEqual(@as(?u64, 1000), plan.options.gas_price);
    try testing.expectEqualStrings("0xabc", plan.options.sender.?);
    try testing.expect(plan.options.execute);
    try testing.expect(!plan.options.simulate);

    // Cleanup
    var owned_opts = tx_request_builder.OwnedProgrammaticRequestOptions{
        .options = options,
        .owned_alias = options.alias,
        .owned_sender = options.sender,
    };
    owned_opts.deinit(allocator);
}

/// Test module re-exports
test "module re-exports are accessible" {
    const testing = std.testing;

    // All types should be accessible through root module
    _ = tx_request_builder.AuthorizationPlan;
    _ = tx_request_builder.OwnedAuthorizationPlan;
    _ = tx_request_builder.TransactionBlock;
    _ = tx_request_builder.InstructionKind;
    _ = tx_request_builder.MoveCallInstruction;
    _ = tx_request_builder.SessionChallenge;
    _ = tx_request_builder.AccountProvider;
    _ = tx_request_builder.CommandResultHandle;
    _ = tx_request_builder.ArgumentValue;

    // Functions should be accessible
    _ = tx_request_builder.authorizationPlan;
    _ = tx_request_builder.ownedAuthorizationPlan;
    _ = tx_request_builder.buildTransactionBlockFromCommandSource;
    _ = tx_request_builder.buildArtifact;
    _ = tx_request_builder.accountProviderCanExecute;
    _ = tx_request_builder.buildSignPersonalMessageChallengeText;
    _ = tx_request_builder.buildSessionChallengeText;
}
