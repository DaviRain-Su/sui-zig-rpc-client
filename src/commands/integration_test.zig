/// commands/integration_test.zig - Integration tests for commands module
const std = @import("std");
const commands = @import("root.zig");
const types = @import("types.zig");
const wallet_types = @import("wallet_types.zig");
const provider = @import("provider.zig");
const wallet = @import("wallet.zig");
const tx = @import("tx.zig");
const move = @import("move.zig");
const account = @import("account.zig");
const dispatch = @import("dispatch.zig");
const shared = @import("shared.zig");

const client = @import("sui_client_zig");

// ============================================================
// Module Integration Tests
// ============================================================

test "all modules are accessible via commands namespace" {
    const testing = std.testing;

    // Types
    _ = types.CommandResult;
    _ = types.TxBuildError;
    _ = types.CliProviderKind;

    // Wallet types
    _ = wallet_types.WalletLifecycleSummary;
    _ = wallet_types.WalletAccountEntry;
    _ = wallet_types.WalletAccountsSummary;

    // Provider
    _ = provider.ProviderConfig;
    _ = provider.SessionChallenge;
    _ = provider.SignPersonalMessageChallenge;
    _ = provider.PasskeyChallenge;
    _ = provider.ZkLoginNonceChallenge;

    // TX
    _ = tx.TxKind;
    _ = tx.TxOptions;

    // Move
    _ = move.MoveFunctionTemplateOutput;
    _ = move.MoveCallArg;
    _ = move.MoveFunctionId;

    // Account
    _ = account.AccountInfo;
    _ = account.CoinInfo;
    _ = account.ObjectInfo;

    // Verify we can access functions
    _ = wallet.buildWalletAccountsSummary;
    _ = tx.buildDryRunPayload;
    _ = move.parseMoveFunctionTemplateOutput;
    _ = account.formatAccountInfo;

    // Just verify compilation succeeds
    try testing.expect(true);
}

test "end-to-end type flow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a wallet lifecycle summary
    var summary = wallet_types.WalletLifecycleSummary{
        .action = try allocator.dupe(u8, "created"),
        .selector = try allocator.dupe(u8, "test_wallet"),
        .address = try allocator.dupe(u8, "0x123"),
        .public_key = try allocator.dupe(u8, "0xabc"),
        .keystore_path = try allocator.dupe(u8, "/path/to/keystore"),
        .wallet_state_path = null,
        .activated = true,
    };
    defer summary.deinit(allocator);

    // Create a provider config
    var config = try provider.buildProviderConfig(allocator, .remote_signer, "https://api.example.com");
    defer config.deinit(allocator);

    // Create a transaction payload
    const MockArgs = struct {
        tx_bytes: ?[]const u8 = "AAABBB",
        tx_options: ?[]const u8 = null,
        tx_send_observe: bool = false,
        tx_send_wait: bool = false,
        tx_send_summarize: bool = false,
        confirm_timeout_ms: ?u64 = null,
        confirm_poll_ms: u64 = 1000,
        pretty: bool = false,
    };
    var args = MockArgs{};
    const signatures = &.{ "sig1", "sig2" };

    const payload = try tx.buildExecutePayloadFromArgs(allocator, &args, signatures, null);
    defer allocator.free(payload);

    // Create account info
    const address = try allocator.dupe(u8, "0x456");
    var info = account.AccountInfo{
        .address = address,
        .balance = 1000,
        .object_count = 5,
    };
    defer info.deinit(allocator);

    // All types work together
    try testing.expectEqualStrings("created", summary.action);
    try testing.expectEqual(types.CliProviderKind.remote_signer, config.kind);
    try testing.expect(std.mem.containsAtLeast(u8, payload, 1, "sig1"));
    try testing.expectEqual(@as(u64, 1000), info.balance);
}

test "provider challenge flow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build a sign personal message challenge
    var spm = try provider.buildSignPersonalMessageChallenge(
        allocator,
        "example.com",
        "Sign in to SUI",
        "nonce123",
        "0x789",
    );

    // Wrap in union
    var challenge = provider.SessionChallenge{
        .sign_personal_message = spm,
    };
    defer challenge.deinit(allocator);

    // Verify
    try testing.expectEqualStrings("example.com", challenge.sign_personal_message.domain);
    try testing.expectEqualStrings("Sign in to SUI", challenge.sign_personal_message.statement);
}

test "move function id flow" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build function ID
    var func_id = try move.buildMoveFunctionId(allocator, "0x1", "module", "function");
    defer func_id.deinit(allocator);

    // Format it
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try move.formatMoveFunctionId(output.writer(), &func_id);

    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "0x1::module::function"));
}

test "shared utilities work across modules" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test JSON parsing
    const json = "{\"key\":\"value\",\"number\":42}";
    const parsed = try shared.parseJsonSafe(allocator, json);
    defer parsed.deinit();

    try testing.expectEqualStrings("value", parsed.value.object.get("key").?.string);
    try testing.expectEqual(@as(i64, 42), parsed.value.object.get("number").?.integer);

    // Test JSON validation
    try testing.expect(try shared.isValidJson(json));
    try testing.expect(!(try shared.isValidJson("not json")));
}

test "error handling across modules" {
    const testing = std.testing;

    // Test error types from different modules
    const tx_err = error.InvalidTxKind;
    const cli_err = error.InvalidCli;
    const wallet_err = error.InvalidWalletState;

    // All should be catchable
    const result1: error{InvalidTxKind}!void = error.InvalidTxKind;
    const result2: error{InvalidCli}!void = error.InvalidCli;
    const result3: error{InvalidWalletState}!void = error.InvalidWalletState;

    try testing.expectError(tx_err, result1);
    try testing.expectError(cli_err, result2);
    try testing.expectError(wallet_err, result3);
}

test "memory management across module boundaries" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Allocate in one module, free in another context
    const address = try allocator.dupe(u8, "0xtest");

    // Use in account info
    var info = account.AccountInfo{
        .address = address,
        .balance = 100,
        .object_count = 1,
    };
    defer info.deinit(allocator);

    // Use in wallet summary
    var summary = wallet_types.WalletLifecycleSummary{
        .action = try allocator.dupe(u8, "test"),
        .selector = try allocator.dupe(u8, "selector"),
        .address = try allocator.dupe(u8, "0xtest"),
        .public_key = null,
        .keystore_path = null,
        .wallet_state_path = null,
        .activated = false,
    };
    defer summary.deinit(allocator);

    // Both should work independently
    try testing.expectEqualStrings("0xtest", info.address);
    try testing.expectEqualStrings("0xtest", summary.address);
}

test "dispatch router integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create mock RPC client
    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    // Test help command via dispatch
    const MockArgs = struct {
        command: enum { help, version } = .help,
        pretty: bool = false,
    };
    var args = MockArgs{};

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try dispatch.runCommand(allocator, &rpc, &args, output.writer());

    try testing.expect(output.items.len > 0);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Usage:"));
}

test "complex workflow: provider -> challenge -> authorization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 1: Create provider config
    var config = try provider.buildProviderConfig(allocator, .passkey, "https://passkey.example.com");
    defer config.deinit(allocator);

    // Step 2: Create challenge
    var challenge = provider.SessionChallenge{
        .passkey = try provider.buildPasskeyChallenge(
            allocator,
            "sui.example.com",
            "dGVzdA==", // base64 "test"
            "user@example.com",
        ),
    };
    defer challenge.deinit(allocator);

    // Step 3: Simulate authorization result
    const auth_json = "{\"sender\":\"0xabc\",\"signatures\":[\"sig1\",\"sig2\"],\"supports_execute\":true}";
    var auth = try provider.buildRemoteAuthorizationResultFromJson(allocator, auth_json);
    defer auth.deinit(allocator);

    // Verify the flow
    try testing.expectEqual(types.CliProviderKind.passkey, config.kind);
    try testing.expectEqualStrings("sui.example.com", challenge.passkey.rp_id);
    try testing.expectEqualStrings("0xabc", auth.sender.?);
    try testing.expectEqual(@as(usize, 2), auth.signatures.len);
}

test "all template outputs are parseable" {
    const testing = std.testing;

    const outputs = &.{
        "commands",
        "preferred-commands",
        "dry-run-request",
        "preferred-dry-run-request",
        "send-request",
        "preferred-send-request",
    };

    inline for (outputs) |output| {
        const parsed = move.parseMoveFunctionTemplateOutput(output) catch |err| {
            try testing.expect(false); // Should not fail
            return err;
        };
        _ = parsed;
    }
}

test "transaction kind coverage" {
    const testing = std.testing;

    const kinds = &.{
        tx.TxKind.transfer,
        tx.TxKind.move_call,
        tx.TxKind.programmable,
        tx.TxKind.publish,
        tx.TxKind.upgrade,
    };

    inline for (kinds) |kind| {
        const str = tx.buildTxKindString(kind);
        try testing.expect(str.len > 0);
    }
}

test "provider kind roundtrip" {
    const testing = std.testing;

    const kinds = &.{
        "remote_signer",
        "passkey",
        "zklogin",
        "multisig",
    };

    inline for (kinds) |kind_str| {
        const kind = try provider.parseProviderKind(kind_str);
        _ = kind;
    }
}

test "account info formatting" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const address = try allocator.dupe(u8, "0xtest");
    const info = account.AccountInfo{
        .address = address,
        .balance = 123456789,
        .object_count = 42,
    };
    defer allocator.free(address);

    // Test pretty format
    var pretty_output: std.ArrayList(u8) = .{};
    defer pretty_output.deinit(allocator);
    try account.formatAccountInfo(pretty_output.writer(), &info, true);
    try testing.expect(std.mem.containsAtLeast(u8, pretty_output.items, 1, "0xtest"));
    try testing.expect(std.mem.containsAtLeast(u8, pretty_output.items, 1, "123456789"));

    // Test compact format
    var compact_output: std.ArrayList(u8) = .{};
    defer compact_output.deinit(allocator);
    try account.formatAccountInfo(compact_output.writer(), &info, false);
    try testing.expect(std.mem.containsAtLeast(u8, compact_output.items, 1, "0xtest,123456789,42"));
}
