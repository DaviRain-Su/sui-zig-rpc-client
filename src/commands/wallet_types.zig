/// commands/wallet_types.zig - Wallet-related type definitions
const std = @import("std");

/// Wallet lifecycle summary (create/import operations)
pub const WalletLifecycleSummary = struct {
    action: []const u8,
    selector: []const u8,
    address: []const u8,
    public_key: ?[]const u8,
    keystore_path: ?[]const u8,
    wallet_state_path: ?[]const u8,
    activated: bool,

    pub fn deinit(self: *WalletLifecycleSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.action);
        allocator.free(self.selector);
        allocator.free(self.address);
        if (self.public_key) |key| allocator.free(key);
        if (self.keystore_path) |path| allocator.free(path);
        if (self.wallet_state_path) |path| allocator.free(path);
    }
};

/// Wallet account list entry
pub const WalletAccountEntry = struct {
    source_kind: []const u8,
    mode: []const u8,
    selector: []const u8,
    label: ?[]const u8,
    address: []const u8,
    public_key: ?[]const u8,
    network: ?[]const u8,
    state: []const u8,
    active_match: bool,
    can_sign_locally: bool,

    pub fn deinit(self: *WalletAccountEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.source_kind);
        allocator.free(self.mode);
        allocator.free(self.selector);
        if (self.label) |label| allocator.free(label);
        allocator.free(self.address);
        if (self.public_key) |key| allocator.free(key);
        if (self.network) |network| allocator.free(network);
        allocator.free(self.state);
    }
};

/// Wallet accounts summary
pub const WalletAccountsSummary = struct {
    artifact_kind: []const u8,
    active_selector: ?[]const u8,
    registry_path: ?[]const u8,
    keystore_path: ?[]const u8,
    entries: []WalletAccountEntry,

    pub fn deinit(self: *WalletAccountsSummary, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(self.entries);
        if (self.active_selector) |selector| allocator.free(selector);
        if (self.registry_path) |path| allocator.free(path);
        if (self.keystore_path) |path| allocator.free(path);
    }
};

/// Wallet stored entry (for keystore)
pub const WalletStoredEntry = struct {
    json: []const u8,
    address: []const u8,
    public_key: ?[]const u8,

    pub fn deinit(self: *WalletStoredEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.json);
        allocator.free(self.address);
        if (self.public_key) |key| allocator.free(key);
    }
};

// ============================================================
// Tests
// ============================================================

test "WalletLifecycleSummary deinit" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = WalletLifecycleSummary{
        .action = try allocator.dupe(u8, "created"),
        .selector = try allocator.dupe(u8, "test"),
        .address = try allocator.dupe(u8, "0x123"),
        .public_key = try allocator.dupe(u8, "pk"),
        .keystore_path = try allocator.dupe(u8, "/path"),
        .wallet_state_path = null,
        .activated = true,
    };
    summary.deinit(allocator);
}
