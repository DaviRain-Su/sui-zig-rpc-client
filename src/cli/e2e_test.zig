/// cli/e2e_test.zig - End-to-end tests for CLI module
const std = @import("std");
const cli = @import("root.zig");
const types = @import("types.zig");
const parsed_args = @import("parsed_args.zig");
const parser = @import("parser.zig");
const validator = @import("validator.zig");
const help = @import("help.zig");
const utils = @import("utils.zig");

// ============================================================
// End-to-End Workflow Tests
// ============================================================

test "e2e: wallet creation workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 1: Parse command
    const args = &[_][]const u8{ "wallet", "create", "--alias", "mywallet", "--json" };
    var parsed = try parser.parseCliArgs(allocator, args);
    defer parsed.deinit(allocator);

    // Step 2: Validate
    try validator.validateArgs(&parsed);

    // Step 3: Verify
    try testing.expectEqual(types.Command.wallet_create, parsed.command);
    try testing.expectEqualStrings("mywallet", parsed.wallet_alias.?);
    try testing.expect(parsed.wallet_json);
}

test "e2e: transaction build and send workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 1: Build transaction
    const build_args = &[_][]const u8{
        "tx", "build",
        "--kind", "move-call",
        "--package", "0x" ++ "1" ** 64,
        "--module", "module",
        "--function", "function",
        "--sender", "0x" ++ "2" ** 64,
        "--gas-budget", "1000000",
    };

    var parsed = try parser.parseCliArgs(allocator, build_args);
    defer parsed.deinit(allocator);

    // Step 2: Validate
    try validator.validateArgs(&parsed);

    // Step 3: Verify build args
    try testing.expectEqual(types.Command.tx_build, parsed.command);
    try testing.expectEqual(types.TxBuildKind.move_call, parsed.tx_build_kind.?);
    try testing.expectEqualStrings("module", parsed.tx_build_module.?);

    // Step 4: Simulate sending
    const send_args = &[_][]const u8{
        "tx", "send", "txbytes",
        "--signature", "sig1",
        "--signature", "sig2",
        "--wait",
    };

    var send_parsed = try parser.parseCliArgs(allocator, send_args);
    defer send_parsed.deinit(allocator);

    try validator.validateArgs(&send_parsed);
    try testing.expectEqual(@as(usize, 2), send_parsed.signatures.items.len);
    try testing.expect(send_parsed.tx_send_wait);
}

test "e2e: account query workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_address = "0x" ++ "1" ** 64;

    // Query balance
    const balance_args = &[_][]const u8{ "account", "balance", test_address, "--json" };
    var parsed = try parser.parseCliArgs(allocator, balance_args);
    defer parsed.deinit(allocator);

    try validator.validateArgs(&parsed);
    try testing.expectEqual(types.Command.account_balance, parsed.command);
    try testing.expect(validator.isValidAddress(test_address));

    // Query coins
    const coins_args = &[_][]const u8{ "account", "coins", test_address, "--json" };
    var coins_parsed = try parser.parseCliArgs(allocator, coins_args);
    defer coins_parsed.deinit(allocator);

    try validator.validateArgs(&coins_parsed);
    try testing.expectEqual(types.Command.account_coins, coins_parsed.command);
}

test "e2e: move inspection workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_package = "0x" ++ "1" ** 64;

    // Inspect package
    const package_args = &[_][]const u8{ "move", "package", test_package, "--summarize" };
    var parsed = try parser.parseCliArgs(allocator, package_args);
    defer parsed.deinit(allocator);

    try validator.validateArgs(&parsed);
    try testing.expect(parsed.move_summarize);

    // Inspect function
    const function_args = &[_][]const u8{
        "move", "function", test_package, "module", "function",
        "--output", "dry-run-request",
        "--summarize",
    };

    var func_parsed = try parser.parseCliArgs(allocator, function_args);
    defer func_parsed.deinit(allocator);

    try validator.validateArgs(&func_parsed);
    try testing.expectEqual(types.MoveFunctionTemplateOutput.tx_dry_run_request, func_parsed.move_function_template_output.?);
}

test "e2e: object query workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_object = "0x" ++ "1" ** 64;

    // Get object
    const object_args = &[_][]const u8{
        "object", "get", test_object,
        "--show-type",
        "--show-content",
    };

    var parsed = try parser.parseCliArgs(allocator, object_args);
    defer parsed.deinit(allocator);

    try validator.validateArgs(&parsed);
    try testing.expect(parsed.object_show_type);
    try testing.expect(parsed.object_show_content);

    // Get dynamic fields
    const fields_args = &[_][]const u8{ "object", "dynamic-fields", test_object, "--limit", "10" };
    var fields_parsed = try parser.parseCliArgs(allocator, fields_args);
    defer fields_parsed.deinit(allocator);

    try validator.validateArgs(&fields_parsed);
    try testing.expectEqual(types.Command.object_dynamic_fields, fields_parsed.command);
}

test "e2e: RPC call workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rpc_args = &[_][]const u8{
        "rpc", "suix_getBalance", "[\"0x" ++ "1" ** 64 ++ "\"]",
    };

    var parsed = try parser.parseCliArgs(allocator, rpc_args);
    defer parsed.deinit(allocator);

    try validator.validateArgs(&parsed);
    try testing.expectEqualStrings("suix_getBalance", parsed.method.?);
    try testing.expect(validator.isValidJson(parsed.params.?));
}

test "e2e: help system workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // General help
    var output1 = std.ArrayList(u8).init(allocator);
    defer output1.deinit();

    try help.printUsage(output1.writer());
    try testing.expect(std.mem.containsAtLeast(u8, output1.items, 1, "Usage:"));

    // Command-specific help
    var output2 = std.ArrayList(u8).init(allocator);
    defer output2.deinit();

    try help.printCommandHelp(output2.writer(), .tx_build);
    try testing.expect(std.mem.containsAtLeast(u8, output2.items, 1, "tx build"));

    // Category help
    var output3 = std.ArrayList(u8).init(allocator);
    defer output3.deinit();

    try help.printCategoryHelp(output3.writer(), .wallet);
    try testing.expect(std.mem.containsAtLeast(u8, output3.items, 1, "Wallet Commands:"));
}

test "e2e: validation error handling" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Missing required arg
    const args1 = &[_][]const u8{ "wallet", "import" };
    var parsed1 = try parser.parseCliArgs(allocator, args1);
    defer parsed1.deinit(allocator);

    try testing.expectError(validator.ValidationError.MissingRequiredArgument, validator.validateArgs(&parsed1));

    // Invalid address
    const args2 = &[_][]const u8{ "account", "info", "invalid_address" };
    var parsed2 = try parser.parseCliArgs(allocator, args2);
    defer parsed2.deinit(allocator);

    try testing.expectError(validator.ValidationError.InvalidAddress, validator.validateArgs(&parsed2));

    // Invalid command combination
    const args3 = &[_][]const u8{ "tx", "send", "bytes", "--wait", "--observe" };
    var parsed3 = try parser.parseCliArgs(allocator, args3);
    defer parsed3.deinit(allocator);

    try testing.expectError(validator.ValidationError.InvalidCommandCombination, validator.validateCommandCombination(&parsed3));
}

test "e2e: utility functions integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Boolean parsing
    try testing.expect(try utils.parseBool("true"));
    try testing.expect(!(try utils.parseBool("false")));

    // Balance formatting
    const balance_str = try utils.formatBalance(allocator, 1_500_000_000);
    defer allocator.free(balance_str);
    try testing.expect(std.mem.containsAtLeast(u8, balance_str, 1, "1.500000000"));

    // Comma-separated list
    const list = try utils.parseCommaSeparatedList(allocator, "a,b,c");
    defer utils.freeCommaSeparatedList(allocator, list);
    try testing.expectEqual(@as(usize, 3), list.len);
}

test "e2e: complex multi-step workflow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 1: Create wallet
    const create_args = &[_][]const u8{ "wallet", "create", "--alias", "testwallet" };
    var parsed = try parser.parseCliArgs(allocator, create_args);
    defer parsed.deinit(allocator);
    try testing.expectEqual(types.Command.wallet_create, parsed.command);

    // Step 2: Build transaction
    const build_args = &[_][]const u8{
        "tx", "build",
        "--kind", "move-call",
        "--package", "0x" ++ "1" ** 64,
        "--module", "test",
        "--function", "mint",
        "--sender", "0x" ++ "2" ** 64,
    };

    var build_parsed = try parser.parseCliArgs(allocator, build_args);
    defer build_parsed.deinit(allocator);
    try testing.expectEqual(types.Command.tx_build, build_parsed.command);

    // Step 3: Query account to check balance
    const balance_args = &[_][]const u8{ "account", "balance", "0x" ++ "2" ** 64 };
    var balance_parsed = try parser.parseCliArgs(allocator, balance_args);
    defer balance_parsed.deinit(allocator);
    try testing.expectEqual(types.Command.account_balance, balance_parsed.command);

    // All steps use consistent types
    try testing.expectEqual(types.CommandCategory.wallet, types.getCommandCategory(parsed.command));
    try testing.expectEqual(types.CommandCategory.transaction, types.getCommandCategory(build_parsed.command));
    try testing.expectEqual(types.CommandCategory.account, types.getCommandCategory(balance_parsed.command));
}

// ============================================================
// Performance Tests
// ============================================================

test "e2e: parsing performance" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = &[_][]const u8{
        "tx", "send", "bytes",
        "--signature", "sig1",
        "--signature", "sig2",
        "--signature", "sig3",
        "--wait",
        "--summarize",
    };

    // Parse multiple times to check for memory leaks
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var parsed = try parser.parseCliArgs(allocator, args);
        parsed.deinit(allocator);
    }
}

test "e2e: validation performance" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = &[_][]const u8{
        "move", "function",
        "0x" ++ "1" ** 64,
        "module",
        "function",
    };

    var parsed = try parser.parseCliArgs(allocator, args);
    defer parsed.deinit(allocator);

    // Validate multiple times
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try validator.validateArgs(&parsed);
    }
}
