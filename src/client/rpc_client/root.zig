/// client/rpc_client/root.zig - RPC client module root
///
/// This module provides the RPC client for interacting with Sui nodes.

const std = @import("std");

// Import sub-modules
pub const error = @import("error.zig");
pub const constants = @import("constants.zig");
pub const utils = @import("utils.zig");

// Re-export commonly used types
pub const ClientError = error.ClientError;
pub const RpcErrorDetail = error.RpcErrorDetail;
pub const TransportStats = error.TransportStats;
pub const ResultWithError = error.ResultWithError;
pub const parseErrorFromJson = error.parseErrorFromJson;

// Re-export constants
pub const default_sui_coin_type = constants.default_sui_coin_type;
pub const default_mainnet_endpoint = constants.default_mainnet_endpoint;
pub const default_testnet_endpoint = constants.default_testnet_endpoint;
pub const default_devnet_endpoint = constants.default_devnet_endpoint;
pub const default_request_timeout_ms = constants.default_request_timeout_ms;
pub const mist_per_sui = constants.mist_per_sui;
pub const mistToSui = constants.mistToSui;
pub const suiToMist = constants.suiToMist;

// Re-export utilities
pub const dupeOptionalString = utils.dupeOptionalString;
pub const dupeStringList = utils.dupeStringList;
pub const freeStringList = utils.freeStringList;
pub const parseJsonResultExists = utils.parseJsonResultExists;
pub const extractExecuteDigest = utils.extractExecuteDigest;
pub const isValidHex = utils.isValidHex;
pub const isValidAddress = utils.isValidAddress;
pub const isValidObjectId = utils.isValidObjectId;

// ============================================================
// Tests
// ============================================================

test "rpc_client module imports successfully" {
    _ = error;
    _ = constants;
    _ = utils;
}

test "re-exports work correctly" {
    const testing = std.testing;

    // Test error type
    const err: ClientError = error.Timeout;
    try testing.expectEqual(error.Timeout, err);

    // Test constant
    try testing.expectEqual(@as(u64, 1_000_000_000), mist_per_sui);

    // Test utility function exists
    _ = isValidAddress;
}
