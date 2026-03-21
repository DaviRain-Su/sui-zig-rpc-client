/// cli/validator.zig - Argument validation
const std = @import("std");
const types = @import("types.zig");
const parsed_args = @import("parsed_args.zig");

const ParsedArgs = parsed_args.ParsedArgs;

/// Validation error
pub const ValidationError = error{
    MissingRequiredArgument,
    InvalidArgumentValue,
    InvalidAddress,
    InvalidObjectId,
    InvalidPackageId,
    InvalidHexString,
    InvalidJson,
    InvalidCommandCombination,
};

/// Validate parsed arguments
pub fn validateArgs(args: *const ParsedArgs) ValidationError!void {
    // Validate command-specific requirements
    switch (args.command) {
        .wallet_import => try validateWalletImportArgs(args),
        .wallet_use => try validateWalletUseArgs(args),
        .account_info => try validateAccountInfoArgs(args),
        .account_balance => try validateAccountBalanceArgs(args),
        .tx_build => try validateTxBuildArgs(args),
        .tx_send => try validateTxSendArgs(args),
        .move_package => try validateMovePackageArgs(args),
        .move_module => try validateMoveModuleArgs(args),
        .move_function => try validateMoveFunctionArgs(args),
        .object_get => try validateObjectGetArgs(args),
        .rpc => try validateRpcArgs(args),
        else => {},
    }
}

/// Validate wallet import arguments
fn validateWalletImportArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.wallet_private_key == null) {
        return ValidationError.MissingRequiredArgument;
    }
}

/// Validate wallet use arguments
fn validateWalletUseArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.wallet_alias == null) {
        return ValidationError.MissingRequiredArgument;
    }
}

/// Validate account info arguments
fn validateAccountInfoArgs(args: *const ParsedArgs) ValidationError!void {
    // Address is optional - will use active wallet if not provided
    if (args.account_selector) |addr| {
        if (!isValidAddress(addr)) {
            return ValidationError.InvalidAddress;
        }
    }
}

/// Validate account balance arguments
fn validateAccountBalanceArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.account_selector) |addr| {
        if (!isValidAddress(addr)) {
            return ValidationError.InvalidAddress;
        }
    }
}

/// Validate transaction build arguments
fn validateTxBuildArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.tx_build_kind == null) {
        return ValidationError.MissingRequiredArgument;
    }

    switch (args.tx_build_kind.?) {
        .move_call => {
            if (args.tx_build_package == null or
                args.tx_build_module == null or
                args.tx_build_function == null)
            {
                return ValidationError.MissingRequiredArgument;
            }

            if (args.tx_build_package) |pkg| {
                if (!isValidPackageId(pkg)) {
                    return ValidationError.InvalidPackageId;
                }
            }
        },
        .programmable => {
            // Programmable transactions need commands
            // This is validated elsewhere
        },
    }
}

/// Validate transaction send arguments
fn validateTxSendArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.tx_bytes == null) {
        return ValidationError.MissingRequiredArgument;
    }

    // tx_bytes should be valid base64 or hex
    if (args.tx_bytes) |bytes| {
        if (!isValidHexOrBase64(bytes)) {
            return ValidationError.InvalidArgumentValue;
        }
    }
}

/// Validate move package arguments
fn validateMovePackageArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.move_package == null) {
        return ValidationError.MissingRequiredArgument;
    }

    if (args.move_package) |pkg| {
        if (!isValidPackageId(pkg)) {
            return ValidationError.InvalidPackageId;
        }
    }
}

/// Validate move module arguments
fn validateMoveModuleArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.move_package == null or args.move_module == null) {
        return ValidationError.MissingRequiredArgument;
    }

    if (args.move_package) |pkg| {
        if (!isValidPackageId(pkg)) {
            return ValidationError.InvalidPackageId;
        }
    }
}

/// Validate move function arguments
fn validateMoveFunctionArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.move_package == null or
        args.move_module == null or
        args.move_function == null)
    {
        return ValidationError.MissingRequiredArgument;
    }

    if (args.move_package) |pkg| {
        if (!isValidPackageId(pkg)) {
            return ValidationError.InvalidPackageId;
        }
    }
}

/// Validate object get arguments
fn validateObjectGetArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.object_id == null) {
        return ValidationError.MissingRequiredArgument;
    }

    if (args.object_id) |id| {
        if (!isValidObjectId(id)) {
            return ValidationError.InvalidObjectId;
        }
    }
}

/// Validate RPC arguments
fn validateRpcArgs(args: *const ParsedArgs) ValidationError!void {
    if (args.method == null) {
        return ValidationError.MissingRequiredArgument;
    }

    // Validate params is valid JSON if provided
    if (args.params) |params| {
        if (!isValidJson(params)) {
            return ValidationError.InvalidJson;
        }
    }
}

/// Check if string is a valid Sui address
pub fn isValidAddress(value: []const u8) bool {
    // Address should start with 0x and be 64 hex chars
    if (!std.mem.startsWith(u8, value, "0x")) return false;

    const hex_part = value[2..];
    if (hex_part.len != 64) return false;

    for (hex_part) |c| {
        if (!isHexDigit(c)) return false;
    }

    return true;
}

/// Check if string is a valid object ID
pub fn isValidObjectId(value: []const u8) bool {
    // Object ID should start with 0x and be 64 hex chars
    return isValidAddress(value);
}

/// Check if string is a valid package ID
pub fn isValidPackageId(value: []const u8) bool {
    // Package ID should start with 0x and be 64 hex chars
    return isValidAddress(value);
}

/// Check if string is valid hex or base64
pub fn isValidHexOrBase64(value: []const u8) bool {
    // Try hex first
    if (std.mem.startsWith(u8, value, "0x")) {
        const hex_part = value[2..];
        for (hex_part) |c| {
            if (!isHexDigit(c)) return false;
        }
        return true;
    }

    // Otherwise check if it's valid base64 chars
    for (value) |c| {
        if (!isBase64Char(c)) return false;
    }
    return true;
}

/// Check if string is valid JSON
pub fn isValidJson(value: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, std.testing.allocator, value, .{}) catch {
        return false;
    };
    parsed.deinit();
    return true;
}

/// Check if character is a hex digit
fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or
           (c >= 'a' and c <= 'f') or
           (c >= 'A' and c <= 'F');
}

/// Check if character is a base64 character
fn isBase64Char(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or
           (c >= 'a' and c <= 'z') or
           (c >= '0' and c <= '9') or
           c == '+' or c == '/' or c == '=';
}

/// Validate that command combination is valid
pub fn validateCommandCombination(args: *const ParsedArgs) ValidationError!void {
    // Can't use --wait and --observe together
    if (args.tx_send_wait and args.tx_send_observe) {
        return ValidationError.InvalidCommandCombination;
    }

    // Can't use --summarize with --observe
    if (args.tx_send_summarize and args.tx_send_observe) {
        return ValidationError.InvalidCommandCombination;
    }
}

/// Validate gas budget
pub fn validateGasBudget(budget: u64) ValidationError!void {
    if (budget == 0) {
        return ValidationError.InvalidArgumentValue;
    }

    // Max gas budget (arbitrary reasonable limit)
    const max_budget: u64 = 1_000_000_000; // 1 SUI
    if (budget > max_budget) {
        return ValidationError.InvalidArgumentValue;
    }
}

/// Validate timeout
pub fn validateTimeout(timeout_ms: u64) ValidationError!void {
    if (timeout_ms == 0) {
        return ValidationError.InvalidArgumentValue;
    }

    // Max timeout (10 minutes)
    const max_timeout: u64 = 600_000;
    if (timeout_ms > max_timeout) {
        return ValidationError.InvalidArgumentValue;
    }
}

// ============================================================
// Tests
// ============================================================

test "isValidAddress validates correct addresses" {
    const testing = std.testing;

    try testing.expect(isValidAddress("0x" ++ "1" ** 64));
    try testing.expect(isValidAddress("0x" ++ "a" ** 64));
    try testing.expect(isValidAddress("0x" ++ "f" ** 64));
}

test "isValidAddress rejects invalid addresses" {
    const testing = std.testing;

    try testing.expect(!isValidAddress("not_an_address"));
    try testing.expect(!isValidAddress("0x123")); // Too short
    try testing.expect(!isValidAddress("0x" ++ "g" ** 64)); // Invalid char
    try testing.expect(!isValidAddress("0x" ++ "1" ** 63)); // Wrong length
}

test "isValidObjectId validates correct IDs" {
    const testing = std.testing;

    try testing.expect(isValidObjectId("0x" ++ "1" ** 64));
}

test "isValidHexOrBase64 validates hex" {
    const testing = std.testing;

    try testing.expect(isValidHexOrBase64("0x1234abcd"));
    try testing.expect(isValidHexOrBase64("0x" ++ "1" ** 64));
}

test "isValidHexOrBase64 validates base64" {
    const testing = std.testing;

    try testing.expect(isValidHexOrBase64("SGVsbG8gV29ybGQ="));
    try testing.expect(isValidHexOrBase64("dGVzdA=="));
}

test "isValidJson validates JSON" {
    const testing = std.testing;

    try testing.expect(isValidJson("{}"));
    try testing.expect(isValidJson("[]"));
    try testing.expect(isValidJson("{\"key\":\"value\"}"));
    try testing.expect(isValidJson("[1,2,3]"));
}

test "isValidJson rejects invalid JSON" {
    const testing = std.testing;

    try testing.expect(!isValidJson("not json"));
    try testing.expect(!isValidJson("{\"key\"}"));
    try testing.expect(!isValidJson(""));
}

test "validateWalletImportArgs requires private key" {
    const testing = std.testing;

    const args1 = ParsedArgs{
        .command = .wallet_import,
        .wallet_private_key = "key123",
    };
    try validateWalletImportArgs(&args1);

    const args2 = ParsedArgs{
        .command = .wallet_import,
        .wallet_private_key = null,
    };
    try testing.expectError(ValidationError.MissingRequiredArgument, validateWalletImportArgs(&args2));
}

test "validateTxBuildArgs requires kind" {
    const testing = std.testing;

    const args1 = ParsedArgs{
        .command = .tx_build,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x" ++ "1" ** 64,
        .tx_build_module = "module",
        .tx_build_function = "func",
    };
    try validateTxBuildArgs(&args1);

    const args2 = ParsedArgs{
        .command = .tx_build,
        .tx_build_kind = null,
    };
    try testing.expectError(ValidationError.MissingRequiredArgument, validateTxBuildArgs(&args2));
}

test "validateTxBuildArgs for move_call requires all fields" {
    const testing = std.testing;

    const args = ParsedArgs{
        .command = .tx_build,
        .tx_build_kind = .move_call,
        .tx_build_package = "0x" ++ "1" ** 64,
        .tx_build_module = null,
        .tx_build_function = null,
    };
    try testing.expectError(ValidationError.MissingRequiredArgument, validateTxBuildArgs(&args));
}

test "validateMovePackageArgs requires package" {
    const testing = std.testing;

    const args1 = ParsedArgs{
        .command = .move_package,
        .move_package = "0x" ++ "1" ** 64,
    };
    try validateMovePackageArgs(&args1);

    const args2 = ParsedArgs{
        .command = .move_package,
        .move_package = null,
    };
    try testing.expectError(ValidationError.MissingRequiredArgument, validateMovePackageArgs(&args2));
}

test "validateObjectGetArgs requires object_id" {
    const testing = std.testing;

    const args1 = ParsedArgs{
        .command = .object_get,
        .object_id = "0x" ++ "1" ** 64,
    };
    try validateObjectGetArgs(&args1);

    const args2 = ParsedArgs{
        .command = .object_get,
        .object_id = null,
    };
    try testing.expectError(ValidationError.MissingRequiredArgument, validateObjectGetArgs(&args2));
}

test "validateRpcArgs requires method" {
    const testing = std.testing;

    const args1 = ParsedArgs{
        .command = .rpc,
        .method = "suix_getBalance",
    };
    try validateRpcArgs(&args1);

    const args2 = ParsedArgs{
        .command = .rpc,
        .method = null,
    };
    try testing.expectError(ValidationError.MissingRequiredArgument, validateRpcArgs(&args2));
}

test "validateCommandCombination rejects invalid combos" {
    const testing = std.testing;

    const args = ParsedArgs{
        .command = .tx_send,
        .tx_send_wait = true,
        .tx_send_observe = true,
    };
    try testing.expectError(ValidationError.InvalidCommandCombination, validateCommandCombination(&args));
}

test "validateGasBudget validates ranges" {
    const testing = std.testing;

    try validateGasBudget(1);
    try validateGasBudget(1_000_000);
    try validateGasBudget(1_000_000_000);

    try testing.expectError(ValidationError.InvalidArgumentValue, validateGasBudget(0));
    try testing.expectError(ValidationError.InvalidArgumentValue, validateGasBudget(2_000_000_000));
}

test "validateTimeout validates ranges" {
    const testing = std.testing;

    try validateTimeout(1);
    try validateTimeout(60_000);
    try validateTimeout(600_000);

    try testing.expectError(ValidationError.InvalidArgumentValue, validateTimeout(0));
    try testing.expectError(ValidationError.InvalidArgumentValue, validateTimeout(601_000));
}
