// Wallet module - Advanced wallet functionality
// Session management, policy enforcement, and secure key operations

const std = @import("std");

pub const advanced = @import("advanced.zig");

// Re-export main types
pub const WalletConfig = advanced.WalletConfig;
pub const Session = advanced.Session;
pub const SessionManager = advanced.SessionManager;
pub const PolicyEngine = advanced.PolicyEngine;
pub const PolicyResult = advanced.PolicyResult;
pub const DailyTracker = advanced.DailyTracker;

// Wallet state
pub const Wallet = struct {
    allocator: std.mem.Allocator,
    address: []const u8,
    session_manager: SessionManager,
    policy_engine: PolicyEngine,

    pub fn init(
        allocator: std.mem.Allocator,
        address: []const u8,
        config: WalletConfig,
    ) !Wallet {
        return .{
            .allocator = allocator,
            .address = try allocator.dupe(u8, address),
            .session_manager = SessionManager.init(allocator),
            .policy_engine = PolicyEngine.init(config),
        };
    }

    pub fn deinit(self: *Wallet) void {
        self.allocator.free(self.address);
        self.session_manager.deinit();
    }

    /// Start new session
    pub fn startSession(
        self: *Wallet,
        auth_method: Session.AuthMethod,
    ) !*Session {
        return try self.session_manager.createSession(
            self.address,
            self.policy_engine.config.session_duration_secs,
            auth_method,
        );
    }

    /// Check if can perform transaction
    pub fn canTransact(
        self: *Wallet,
        recipient: []const u8,
        amount: u64,
    ) PolicyResult {
        const session = self.session_manager.getActiveSession(self.address);
        return self.policy_engine.checkTransaction(session, recipient, amount);
    }

    /// Record transaction
    pub fn recordTransaction(self: *Wallet, amount: u64) void {
        if (self.session_manager.getActiveSession(self.address)) |session| {
            self.policy_engine.recordTransaction(session, amount);
        }
    }

    /// Get wallet status
    pub fn getStatus(self: *Wallet) WalletStatus {
        const session = self.session_manager.getActiveSession(self.address);

        return .{
            .address = self.address,
            .session_active = session != null,
            .session_expires = if (session) |s| s.expires_at else 0,
            .session_spent = if (session) |s| s.session_spent else 0,
            .daily_spent = self.policy_engine.daily_tracker.total_spent,
            .daily_limit = self.policy_engine.config.daily_limit,
            .remaining_daily = self.policy_engine.remainingDailyLimit(),
        };
    }
};

pub const WalletStatus = struct {
    address: []const u8,
    session_active: bool,
    session_expires: i64,
    session_spent: u64,
    daily_spent: u64,
    daily_limit: u64,
    remaining_daily: u64,
};

test "Wallet lifecycle" {
    const allocator = std.testing.allocator;

    const config = WalletConfig{
        .max_single_tx_amount = 1000,
        .session_duration_secs = 3600,
    };

    var wallet = try Wallet.init(allocator, "0x1234", config);
    defer wallet.deinit();

    // Start session
    const session = try wallet.startSession(.password);
    try std.testing.expect(session.isValid());

    // Check transaction
    const result = wallet.canTransact("0x5678", 500);
    try std.testing.expect(result.allowed);

    // Get status
    const status = wallet.getStatus();
    try std.testing.expect(status.session_active);
}
