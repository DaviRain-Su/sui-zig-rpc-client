/// commands/root.zig - Commands module root
///
/// This is the root file for the commands module.
/// It re-exports all sub-modules.

const std = @import("std");

// Import sub-modules
pub const types = @import("types.zig");
pub const wallet_types = @import("wallet_types.zig");
pub const shared = @import("shared.zig");
pub const provider = @import("provider.zig");
pub const wallet = @import("wallet.zig");
pub const tx = @import("tx.zig");
pub const move_cmd = @import("move.zig");
pub const account = @import("account.zig");
pub const dispatch = @import("dispatch.zig");

// Re-export main entry points for backward compatibility
pub const runCommand = dispatch.runCommand;
pub const runCommandWithProgrammaticProvider = dispatch.runCommand;

// Re-export types for backward compatibility
pub const CommandResult = types.CommandResult;
pub const TxBuildError = types.TxBuildError;
pub const MoveFunctionTemplateOutput = move_cmd.MoveFunctionTemplateOutput;
pub const WalletLifecycleSummary = wallet_types.WalletLifecycleSummary;
pub const WalletAccountEntry = wallet_types.WalletAccountEntry;
pub const WalletAccountsSummary = wallet_types.WalletAccountsSummary;

// ============================================================
// Tests
// ============================================================

test "commands module imports successfully" {
    _ = types;
    _ = wallet_types;
    _ = shared;
    _ = provider;
    _ = wallet;
    _ = tx;
    _ = move_cmd;
    _ = account;
    _ = dispatch;
}

test "backward compatibility exports work" {
    const testing = std.testing;

    // Verify type exports
    const result: CommandResult = .{ .success = "test" };
    try testing.expectEqualStrings("test", result.success);

    // Verify error type export
    const err: TxBuildError = error.InvalidCli;
    try testing.expectEqual(error.InvalidCli, err);
}

// Import integration tests
comptime {
    _ = @import("integration_test.zig");
}
