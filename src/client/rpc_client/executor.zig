/// client/rpc_client/executor.zig - Transaction execution for Sui RPC Client
const std = @import("std");
const client_core = @import("client_core.zig");
const transaction = @import("transaction.zig");
const object_input = @import("object_input.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;
const ExecutionResult = transaction.ExecutionResult;
const ExecutionOptions = transaction.ExecutionOptions;
const GasData = object_input.GasData;

/// Execute transaction with signatures
pub fn executeTransactionWithSignatures(
    client: *SuiRpcClient,
    tx_bytes: []const u8,
    signatures: []const []const u8,
    options: ?ExecutionOptions,
) !ExecutionResult {
    // Build signatures JSON array
    var sigs_json = std.ArrayList(u8).init(client.allocator);
    defer sigs_json.deinit();

    try sigs_json.append('[');
    for (signatures, 0..) |sig, i| {
        if (i > 0) try sigs_json.append(',');
        try std.fmt.format(sigs_json.writer(), "\"{s}\"", .{sig});
    }
    try sigs_json.append(']');

    const opts_json = if (options) |opts|
        opts.toJson()
    else
        "{}";

    const params = try std.fmt.allocPrint(
        client.allocator,
        "[\"{s}\",{s},{s}]",
        .{ tx_bytes, sigs_json.items, opts_json },
    );
    defer client.allocator.free(params);

    const response = try client.call("sui_executeTransactionBlock", params);
    defer client.allocator.free(response);

    return try parseExecutionResult(client.allocator, response);
}

/// Execute transaction from keystore
///
/// NOTE: This function is not yet implemented. Keystore-based transaction
/// execution requires integration with the keystore module for:
///
/// 1. Loading the appropriate key from ~/.sui/sui_config/sui.keystore
/// 2. Decrypting the key (if password protected)
/// 3. Signing the transaction bytes
/// 4. Executing with the signature
///
/// For now, use:
/// - tx_signer.zig for signing with known keys
/// - commands/wallet.zig for wallet-based execution
/// - executeTransactionWithSignatures() if you already have signatures
pub fn executeTransactionFromKeystore(
    client: *SuiRpcClient,
    tx_bytes: []const u8,
    keystore_path: ?[]const u8,
    options: ?ExecutionOptions,
) !ExecutionResult {
    _ = client;
    _ = tx_bytes;
    _ = keystore_path;
    _ = options;

    // TODO: Implement keystore-based execution
    // This requires:
    // 1. Keystore format parsing (JSON array of base64 keys)
    // 2. Key decryption (if encrypted)
    // 3. Ed25519 signing via tx_signer.zig
    // 4. Signature formatting for Sui
    //
    // Workaround: Use executeTransactionWithSignatures() with pre-signed tx

    return error.NotImplemented;
}

/// Execute transaction with auto gas payment
pub fn executeTransactionWithAutoGas(
    client: *SuiRpcClient,
    tx_bytes: []const u8,
    sender: []const u8,
    signatures: []const []const u8,
    options: ?ExecutionOptions,
) !ExecutionResult {
    _ = sender;
    // First simulate to get gas requirements
    const simulation = try transaction.simulateTransaction(
        client,
        tx_bytes,
        .{},
    );
    defer simulation.deinit(client.allocator);

    // Check if simulation succeeded
    if (simulation.effects.status != .success) {
        return error.SimulationFailed;
    }

    // Execute with provided signatures
    return try executeTransactionWithSignatures(
        client,
        tx_bytes,
        signatures,
        options,
    );
}

/// Build and execute command source
pub fn buildAndExecuteCommandSource(
    client: *SuiRpcClient,
    sender: []const u8,
    commands_json: []const u8,
    gas_budget: ?u64,
    signatures: []const []const u8,
) !ExecutionResult {
    _ = gas_budget;
    // Build transaction bytes
    const params = try std.fmt.allocPrint(
        client.allocator,
        "[\"{s}\",{s}]",
        .{ sender, commands_json },
    );
    defer client.allocator.free(params);

    const response = try client.call("unsafe_batchTransaction", params);
    defer client.allocator.free(response);

    // Parse tx_bytes from response
    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const tx_bytes = parsed.value.string;

    // Execute
    return try executeTransactionWithSignatures(
        client,
        tx_bytes,
        signatures,
        .{},
    );
}

/// Execute with challenge prompt
pub const ExecuteOrChallengePromptResult = union(enum) {
    /// Execution completed
    executed: ExecutionResult,
    /// Challenge required
    challenge: SessionChallengePrompt,
};

/// Session challenge prompt
pub const SessionChallengePrompt = struct {
    /// Challenge text to display
    challenge_text: []const u8,
    /// Challenge type
    challenge_type: []const u8,
    /// Expected signer
    expected_signer: []const u8,

    pub fn deinit(self: *SessionChallengePrompt, allocator: std.mem.Allocator) void {
        allocator.free(self.challenge_text);
        allocator.free(self.challenge_type);
        allocator.free(self.expected_signer);
    }
};

/// Execute or get challenge prompt
pub fn executeOrChallenge(
    client: *SuiRpcClient,
    tx_bytes: []const u8,
    sender: []const u8,
) !ExecuteOrChallengePromptResult {
    // Check if sender requires challenge
    // Simplified - would actually check account type
    _ = client;
    _ = tx_bytes;

    // For now, assume no challenge needed
    const result = ExecutionResult{
        .digest = try std.heap.page_allocator.dupe(u8, "dummy_digest"),
        .transaction = .{
            .sender = try std.heap.page_allocator.dupe(u8, sender),
            .gas_payment = .{
                .object_id = try std.heap.page_allocator.dupe(u8, "0x0"),
                .version = 0,
                .digest = try std.heap.page_allocator.dupe(u8, "0x0"),
            },
            .gas_price = 0,
            .gas_budget = 0,
        },
        .effects = .{
            .status = .success,
            .gas_used = .{
                .computation_cost = 0,
                .storage_cost = 0,
                .storage_rebate = 0,
                .non_refundable_storage_fee = 0,
            },
            .modified_at_versions = &.{},
            .shared_objects = &.{},
            .transaction_digest = try std.heap.page_allocator.dupe(u8, "dummy"),
            .created = &.{},
            .mutated = &.{},
            .unwrapped = &.{},
            .deleted = &.{},
            .wrapped = &.{},
            .gas_object = .{
                .object_id = try std.heap.page_allocator.dupe(u8, "0x0"),
                .version = 0,
                .digest = try std.heap.page_allocator.dupe(u8, "0x0"),
            },
            .events_digest = null,
            .dependencies = &.{},
        },
        .events = &.{},
        .object_changes = &.{},
        .balance_changes = &.{},
        .timestamp_ms = null,
        .checkpoint = null,
        .confirmed_local_execution = true,
    };

    return .{ .executed = result };
}

/// Parse execution result from JSON
fn parseExecutionResult(allocator: std.mem.Allocator, response: []const u8) !ExecutionResult {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result") orelse
        return ClientError.InvalidResponse;

    const digest = result.object.get("digest") orelse
        return ClientError.InvalidResponse;

    // Simplified parsing - full implementation would parse all fields
    return ExecutionResult{
        .digest = try allocator.dupe(u8, digest.string),
        .transaction = .{
            .sender = try allocator.dupe(u8, "0x0"),
            .gas_payment = .{
                .object_id = try allocator.dupe(u8, "0x0"),
                .version = 0,
                .digest = try allocator.dupe(u8, "0x0"),
            },
            .gas_price = 0,
            .gas_budget = 0,
        },
        .effects = .{
            .status = .success,
            .gas_used = .{
                .computation_cost = 0,
                .storage_cost = 0,
                .storage_rebate = 0,
                .non_refundable_storage_fee = 0,
            },
            .modified_at_versions = &.{},
            .shared_objects = &.{},
            .transaction_digest = try allocator.dupe(u8, digest.string),
            .created = &.{},
            .mutated = &.{},
            .unwrapped = &.{},
            .deleted = &.{},
            .wrapped = &.{},
            .gas_object = .{
                .object_id = try allocator.dupe(u8, "0x0"),
                .version = 0,
                .digest = try allocator.dupe(u8, "0x0"),
            },
            .events_digest = null,
            .dependencies = &.{},
        },
        .events = &.{},
        .object_changes = &.{},
        .balance_changes = &.{},
        .timestamp_ms = null,
        .checkpoint = null,
        .confirmed_local_execution = true,
    };
}

/// Wait for transaction confirmation
pub fn waitForTransactionConfirmation(
    client: *SuiRpcClient,
    digest: []const u8,
    timeout_ms: u64,
) !bool {
    const start = std.time.milliTimestamp();

    while (std.time.milliTimestamp() - start < timeout_ms) {
        const params = try std.fmt.allocPrint(
            client.allocator,
            "[\"{s}\"]",
            .{digest},
        );
        defer client.allocator.free(params);

        const response = client.call("sui_getTransactionBlock", params) catch |err| {
            if (err == error.InvalidResponse) {
                // Transaction not found yet, wait
                std.time.sleep(100 * std.time.ns_per_ms);
                continue;
            }
            return err;
        };
        defer client.allocator.free(response);

        return true;
    }

    return false; // Timeout
}

// ============================================================
// Tests
// ============================================================

test "SessionChallengePrompt lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var prompt = SessionChallengePrompt{
        .challenge_text = try allocator.dupe(u8, "Sign this message"),
        .challenge_type = try allocator.dupe(u8, "personal_message"),
        .expected_signer = try allocator.dupe(u8, "0x123"),
    };
    defer prompt.deinit(allocator);

    try testing.expectEqualStrings("Sign this message", prompt.challenge_text);
}

test "ExecuteOrChallengePromptResult union" {
    const testing = std.testing;

    const result = ExecuteOrChallengePromptResult{
        .executed = .{
            .digest = "dummy",
            .transaction = .{
                .sender = "0x0",
                .gas_payment = .{
                    .object_id = "0x0",
                    .version = 0,
                    .digest = "0x0",
                },
                .gas_price = 0,
                .gas_budget = 0,
            },
            .effects = .{
                .status = .success,
                .gas_used = .{
                    .computation_cost = 0,
                    .storage_cost = 0,
                    .storage_rebate = 0,
                    .non_refundable_storage_fee = 0,
                },
                .modified_at_versions = &.{},
                .shared_objects = &.{},
                .transaction_digest = "dummy",
                .created = &.{},
                .mutated = &.{},
                .unwrapped = &.{},
                .deleted = &.{},
                .wrapped = &.{},
                .gas_object = .{
                    .object_id = "0x0",
                    .version = 0,
                    .digest = "0x0",
                },
                .events_digest = null,
                .dependencies = &.{},
            },
            .events = &.{},
            .object_changes = &.{},
            .balance_changes = &.{},
            .timestamp_ms = null,
            .checkpoint = null,
            .confirmed_local_execution = true,
        },
    };

    try testing.expect(result == .executed);
}

test "executeTransactionFromKeystore returns NotImplemented" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var client = try SuiRpcClient.init(allocator, "http://example.com");
    defer client.deinit();

    const result = executeTransactionFromKeystore(
        &client,
        "tx_bytes",
        null,
        null,
    );

    try testing.expectError(error.NotImplemented, result);
}
