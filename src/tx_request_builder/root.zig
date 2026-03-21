/// tx_request_builder/root.zig - Transaction request builder module root
const std = @import("std");

// Import sub-modules
pub const types = @import("types.zig");
pub const argument = @import("argument.zig");
pub const account = @import("account.zig");
pub const session = @import("session.zig");

// Re-export types
pub const CommandResultAliases = types.CommandResultAliases;
pub const NestedResultSpec = types.NestedResultSpec;
pub const ProgrammaticRequestOptions = types.ProgrammaticRequestOptions;
pub const CommandRequestConfig = types.CommandRequestConfig;
pub const ProgrammaticArtifactKind = types.ProgrammaticArtifactKind;
pub const AccountSessionKind = types.AccountSessionKind;
pub const ResolvedCommandValue = types.ResolvedCommandValue;
pub const ResolvedCommandValues = types.ResolvedCommandValues;
pub const FutureWalletAccount = types.FutureWalletAccount;

// Re-export argument types
pub const ArgumentValue = argument.ArgumentValue;
pub const ObjectReference = argument.ObjectReference;
pub const CommandResultHandle = argument.CommandResultHandle;
pub const CommandOutputHandle = argument.CommandOutputHandle;
pub const PtbArgumentSpec = argument.PtbArgumentSpec;
pub const ResolvedArgumentValue = argument.ResolvedArgumentValue;
pub const OwnedArgumentValues = argument.OwnedArgumentValues;
pub const OwnedCommandResultHandles = argument.OwnedCommandResultHandles;
pub const ResolvedPtbArgumentSpec = argument.ResolvedPtbArgumentSpec;
pub const ResolvedPtbArgumentSpecs = argument.ResolvedPtbArgumentSpecs;
pub const ArgumentVectorValue = argument.ArgumentVectorValue;
pub const ArgumentOptionValue = argument.ArgumentOptionValue;

// Re-export account types
pub const AccountProvider = account.AccountProvider;
pub const DirectSignatureAccount = account.DirectSignatureAccount;
pub const KeystoreContentsAccount = account.KeystoreContentsAccount;
pub const DefaultKeystoreAccount = account.DefaultKeystoreAccount;
pub const RemoteSignerAccount = account.RemoteSignerAccount;
pub const accountProviderCanExecute = account.accountProviderCanExecute;
pub const RemoteAuthorizationRequest = account.RemoteAuthorizationRequest;
pub const RemoteAuthorizationResult = account.RemoteAuthorizationResult;
pub const RemoteAuthorizer = account.RemoteAuthorizer;

// Re-export session types
pub const SessionChallenge = session.SessionChallenge;
pub const SignPersonalMessageChallenge = session.SignPersonalMessageChallenge;
pub const PasskeyChallenge = session.PasskeyChallenge;
pub const ZkLoginNonceChallenge = session.ZkLoginNonceChallenge;
pub const SessionChallengeRequest = session.SessionChallengeRequest;
pub const SessionChallengeResponse = session.SessionChallengeResponse;
pub const SessionChallenger = session.SessionChallenger;
pub const buildSignPersonalMessageChallengeText = session.buildSignPersonalMessageChallengeText;
pub const buildSessionChallengeText = session.buildSessionChallengeText;

// ============================================================
// Tests
// ============================================================

test "tx_request_builder module imports successfully" {
    _ = types;
    _ = argument;
    _ = account;
    _ = session;
}

test "re-exports work correctly" {
    const testing = std.testing;

    // Test types
    _ = CommandResultAliases{};
    _ = NestedResultSpec{ .command_index = 0, .result_index = 0 };

    // Test argument types
    _ = ArgumentValue{ .gas = {} };
    _ = CommandResultHandle{ .command_index = 0 };

    // Test account types
    _ = AccountProvider{ .direct = .{
        .private_key = "key",
        .address = "0x123",
        .key_scheme = "ed25519",
    } };

    // Test session types
    _ = SessionChallenge{ .none = {} };
    _ = SessionChallengeRequest{
        .challenge = .{ .none = {} },
        .account_id = "account",
        .timestamp_ms = 0,
    };

    // Test functions exist
    _ = accountProviderCanExecute;
    _ = buildSignPersonalMessageChallengeText;
    _ = buildSessionChallengeText;
}

test "end-to-end type usage" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a command result handle
    const handle = CommandResultHandle{ .command_index = 5 };
    try testing.expectEqual(@as(u16, 5), handle.command_index);

    // Create an output handle
    const output = handle.output(2);
    try testing.expectEqual(@as(u16, 5), output.command_index);
    try testing.expectEqual(@as(u16, 2), output.result_index);

    // Create an account provider
    var provider = AccountProvider{
        .direct = .{
            .private_key = try allocator.dupe(u8, "key"),
            .address = try allocator.dupe(u8, "0x123"),
            .key_scheme = try allocator.dupe(u8, "ed25519"),
        },
    };
    defer provider.deinit(allocator);

    try testing.expect(accountProviderCanExecute(provider));

    // Create a session challenge
    var challenge = SessionChallenge{
        .sign_personal_message = .{
            .message = try allocator.dupe(u8, "authorize"),
            .expected_signer = try allocator.dupe(u8, "0x123"),
        },
    };
    defer challenge.deinit(allocator);

    const text = try buildSignPersonalMessageChallengeText(challenge.sign_personal_message);
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "0x123"));
}
