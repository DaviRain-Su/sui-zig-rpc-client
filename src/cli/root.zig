/// cli/root.zig - CLI module root
///
/// This module provides command-line argument parsing and validation.

const std = @import("std");

// Import sub-modules
pub const types = @import("types.zig");
pub const parsed_args = @import("parsed_args.zig");
pub const parser = @import("parser.zig");

// Re-export commonly used types
pub const Command = types.Command;
pub const TxBuildKind = types.TxBuildKind;
pub const MoveFunctionTemplateOutput = types.MoveFunctionTemplateOutput;
pub const CommandCategory = types.CommandCategory;
pub const ParsedArgs = parsed_args.ParsedArgs;

// Re-export commonly used functions
pub const getCommandCategory = types.getCommandCategory;
pub const isWalletCommand = types.isWalletCommand;
pub const isAccountCommand = types.isAccountCommand;
pub const isTransactionCommand = types.isTransactionCommand;
pub const parseMoveFunctionTemplateOutput = types.parseMoveFunctionTemplateOutput;
pub const hasMoveCallArgs = parsed_args.hasMoveCallArgs;
pub const hasCompleteMoveCallArgs = parsed_args.hasCompleteMoveCallArgs;
pub const hasProgrammaticTxInput = parsed_args.hasProgrammaticTxInput;
pub const validateProgrammaticTxInput = parsed_args.validateProgrammaticTxInput;
pub const supportsProgrammableInput = parsed_args.supportsProgrammableInput;
pub const parseCliArgs = parser.parseCliArgs;

// ============================================================
// Tests
// ============================================================

test "cli module imports successfully" {
    _ = types;
    _ = parsed_args;
    _ = parser;
}

test "re-exports work correctly" {
    const testing = std.testing;

    // Test type re-exports
    const cmd: Command = .help;
    try testing.expectEqual(Command.help, cmd);

    const kind: TxBuildKind = .move_call;
    try testing.expectEqual(TxBuildKind.move_call, kind);

    // Test function re-exports
    try testing.expect(isWalletCommand(.wallet_create));
    try testing.expect(!isWalletCommand(.account_list));
}
