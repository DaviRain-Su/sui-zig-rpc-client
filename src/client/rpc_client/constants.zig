/// client/rpc_client/constants.zig - Constants for RPC client
const std = @import("std");

/// Default SUI coin type
pub const default_sui_coin_type = "0x2::sui::SUI";

/// Default RPC endpoints
pub const default_mainnet_endpoint = "https://fullnode.mainnet.sui.io:443";
pub const default_testnet_endpoint = "https://fullnode.testnet.sui.io:443";
pub const default_devnet_endpoint = "https://fullnode.devnet.sui.io:443";

/// Default timeouts (milliseconds)
pub const default_request_timeout_ms: u64 = 30_000;
pub const default_confirm_timeout_ms: u64 = 60_000;
pub const default_poll_interval_ms: u64 = 2_000;

/// Gas constants
pub const default_gas_budget: u64 = 50_000_000;
pub const min_gas_budget: u64 = 1_000;
pub const max_gas_budget: u64 = 50_000_000_000;

/// MIST per SUI
pub const mist_per_sui: u64 = 1_000_000_000;

/// Maximum request size (10MB)
pub const max_request_size: usize = 10 * 1024 * 1024;

/// Maximum response size (10MB)
pub const max_response_size: usize = 10 * 1024 * 1024;

/// Rate limiting
pub const default_rate_limit_requests_per_second: u64 = 10;
pub const default_rate_limit_burst_size: u64 = 20;

/// Retry configuration
pub const default_max_retries: u32 = 3;
pub const default_retry_delay_ms: u64 = 1_000;

/// Pagination defaults
pub const default_page_limit: u64 = 50;
pub const max_page_limit: u64 = 1_000;

/// Convert MIST to SUI
pub fn mistToSui(mist: u64) f64 {
    return @as(f64, @floatFromInt(mist)) / @as(f64, @floatFromInt(mist_per_sui));
}

/// Convert SUI to MIST
pub fn suiToMist(sui: f64) u64 {
    return @intFromFloat(sui * @as(f64, @floatFromInt(mist_per_sui)));
}

/// Format MIST as SUI string
pub fn formatMistAsSui(mist: u64, buf: []u8) ![]const u8 {
    const sui = mistToSui(mist);
    return try std.fmt.bufPrint(buf, "{d:.9}", .{sui});
}

// ============================================================
// Tests
// ============================================================

test "mistToSui conversion" {
    const testing = std.testing;

    try testing.expectApproxEqAbs(@as(f64, 1.0), mistToSui(1_000_000_000), 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 0.5), mistToSui(500_000_000), 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 0.001), mistToSui(1_000_000), 0.0001);
}

test "suiToMist conversion" {
    const testing = std.testing;

    try testing.expectEqual(@as(u64, 1_000_000_000), suiToMist(1.0));
    try testing.expectEqual(@as(u64, 500_000_000), suiToMist(0.5));
    try testing.expectEqual(@as(u64, 1_000_000), suiToMist(0.001));
}

test "formatMistAsSui" {
    const testing = std.testing;

    var buf: [64]u8 = undefined;
    const result = try formatMistAsSui(1_500_000_000, &buf);
    try testing.expectEqualStrings("1.500000000", result);
}

test "gas budget constants" {
    const testing = std.testing;

    try testing.expect(min_gas_budget < default_gas_budget);
    try testing.expect(default_gas_budget < max_gas_budget);
}

test "page limit constants" {
    const testing = std.testing;

    try testing.expect(default_page_limit <= max_page_limit);
}
