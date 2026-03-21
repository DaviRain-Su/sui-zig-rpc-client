/// commands/types.zig - Shared type definitions
const std = @import("std");

/// Transaction build error
pub const TxBuildError = error{
    InvalidCli,
    InvalidConfig,
    NetworkError,
    RpcError,
    Timeout,
    OutOfMemory,
} || std.mem.Allocator.Error;

/// Command result union
pub const CommandResult = union(enum) {
    success: []const u8,
    challenge_required: []const u8,
    err: TxBuildError,

    pub fn deinit(self: *CommandResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |value| allocator.free(value),
            .challenge_required => |value| allocator.free(value),
            .err => {},
        }
    }
};

/// Wallet entry source kind
pub const WalletEntrySourceKind = enum {
    keystore,
    passkey,
    session,
};

/// Wallet state
pub const WalletState = enum {
    active,
    locked,
    expired,
};

/// CLI provider kind
pub const CliProviderKind = enum {
    remote_signer,
    passkey,
    zklogin,
    multisig,
};

// ============================================================
// Tests
// ============================================================

test "TxBuildError can be caught" {
    const testing = std.testing;
    const err: TxBuildError = error.InvalidCli;
    try testing.expectEqual(error.InvalidCli, err);
}

test "CommandResult deinit frees success" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const value = try allocator.dupe(u8, "test");
    var result = CommandResult{ .success = value };
    result.deinit(allocator);
}
