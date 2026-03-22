// Advanced Wallet - Session Management and Policy Enforcement
// Production-ready secure wallet with spending controls

const std = @import("std");
const Allocator = std.mem.Allocator;
const crypto = std.crypto;

/// Wallet configuration
pub const WalletConfig = struct {
    /// Maximum transaction amount per session (in MIST)
    max_session_amount: u64 = 100_000_000_000, // 100 SUI default

    /// Maximum single transaction amount (in MIST)
    max_single_tx_amount: u64 = 10_000_000_000, // 10 SUI default

    /// Session duration in seconds
    session_duration_secs: u64 = 3600, // 1 hour default

    /// Require confirmation for transactions above threshold
    confirmation_threshold: u64 = 1_000_000_000, // 1 SUI

    /// Allowed recipient addresses (empty = any)
    allowed_recipients: [][]const u8 = &.{},

    /// Blocked recipient addresses
    blocked_recipients: [][]const u8 = &.{},

    /// Daily spending limit (in MIST)
    daily_limit: u64 = 500_000_000_000, // 500 SUI default

    /// Require biometric/PIN for high-value transactions
    require_auth_threshold: u64 = 5_000_000_000, // 5 SUI
};

/// Transaction policy check result
pub const PolicyResult = struct {
    allowed: bool,
    reason: ?[]const u8 = null,
    requires_confirmation: bool = false,
    requires_auth: bool = false,
};

/// Active session
pub const Session = struct {
    /// Session ID (random 32 bytes)
    id: [32]u8,

    /// Wallet address
    address: []const u8,

    /// Session start time
    created_at: i64,

    /// Session expiration time
    expires_at: i64,

    /// Total amount spent in this session
    session_spent: u64 = 0,

    /// Transaction count in this session
    tx_count: u32 = 0,

    /// Last activity timestamp
    last_activity: i64,

    /// Is session active
    active: bool = true,

    /// Authentication method used
    auth_method: AuthMethod,

    /// allocator for cleanup
    allocator: Allocator,

    pub const AuthMethod = enum {
        password,
        biometric,
        hardware_key,
        passkey,
    };

    /// Create new session
    pub fn create(
        allocator: Allocator,
        address: []const u8,
        duration_secs: u64,
        auth_method: AuthMethod,
    ) !Session {
        var session: Session = undefined;
        session.allocator = allocator;

        // Generate random session ID
        crypto.random.bytes(&session.id);

        // Copy address
        session.address = try allocator.dupe(u8, address);
        errdefer allocator.free(session.address);

        // Set timestamps
        const now = std.time.timestamp();
        session.created_at = now;
        session.expires_at = now + @as(i64, @intCast(duration_secs));
        session.last_activity = now;
        session.session_spent = 0;
        session.tx_count = 0;
        session.active = true;
        session.auth_method = auth_method;

        return session;
    }

    /// Destroy session and free resources
    pub fn destroy(self: *Session) void {
        self.active = false;
        self.allocator.free(self.address);
    }

    /// Check if session is valid
    pub fn isValid(self: *const Session) bool {
        if (!self.active) return false;
        const now = std.time.timestamp();
        return now < self.expires_at;
    }

    /// Update activity timestamp
    pub fn touch(self: *Session) void {
        self.last_activity = std.time.timestamp();
    }

    /// Record a transaction
    pub fn recordTransaction(self: *Session, amount: u64) void {
        self.session_spent += amount;
        self.tx_count += 1;
        self.touch();
    }

    /// Get remaining time in seconds
    pub fn remainingSecs(self: *const Session) i64 {
        const now = std.time.timestamp();
        return self.expires_at - now;
    }
};

/// Daily spending tracker
pub const DailyTracker = struct {
    /// Date string (YYYY-MM-DD)
    date: [10]u8,

    /// Total spent today
    total_spent: u64 = 0,

    /// Transaction count
    tx_count: u32 = 0,

    /// Initialize with current date
    pub fn init() DailyTracker {
        var tracker: DailyTracker = undefined;
        tracker.date = getCurrentDate();
        tracker.total_spent = 0;
        tracker.tx_count = 0;
        return tracker;
    }

    /// Check if tracker is for today
    pub fn isToday(self: *const DailyTracker) bool {
        return std.mem.eql(u8, &self.date, &getCurrentDate());
    }

    /// Reset for new day
    pub fn reset(self: *DailyTracker) void {
        self.date = getCurrentDate();
        self.total_spent = 0;
        self.tx_count = 0;
    }

    /// Record spending
    pub fn record(self: *DailyTracker, amount: u64) void {
        if (!self.isToday()) {
            self.reset();
        }
        self.total_spent += amount;
        self.tx_count += 1;
    }

    /// Get current date as string
    fn getCurrentDate() [10]u8 {
        const now = std.time.timestamp();
        const days_since_epoch = @divFloor(now, 86400);
        const epoch_year = 1970;

        // Simple date calculation (approximate)
        var year: i64 = epoch_year;
        var days_remaining = days_since_epoch;

        while (days_remaining >= daysInYear(year)) {
            days_remaining -= daysInYear(year);
            year += 1;
        }

        var month: i64 = 1;
        while (days_remaining >= daysInMonth(year, month)) {
            days_remaining -= daysInMonth(year, month);
            month += 1;
        }

        const day = days_remaining + 1;

        var result: [10]u8 = undefined;
        _ = std.fmt.bufPrint(&result, "{d:04}-{d:02}-{d:02}", .{ year, month, day }) catch {
            return "1970-01-01".*;
        };
        return result;
    }

    fn daysInYear(year: i64) i64 {
        return if (isLeapYear(year)) 366 else 365;
    }

    fn isLeapYear(year: i64) bool {
        return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
    }

    fn daysInMonth(year: i64, month: i64) i64 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(year)) 29 else 28,
            else => 30,
        };
    }
};

/// Policy engine
pub const PolicyEngine = struct {
    config: WalletConfig,
    daily_tracker: DailyTracker,

    pub fn init(config: WalletConfig) PolicyEngine {
        return .{
            .config = config,
            .daily_tracker = DailyTracker.init(),
        };
    }

    /// Check if transaction is allowed
    pub fn checkTransaction(
        self: *PolicyEngine,
        session: ?*const Session,
        recipient: []const u8,
        amount: u64,
    ) PolicyResult {
        // Check session validity
        if (session) |s| {
            if (!s.isValid()) {
                return .{
                    .allowed = false,
                    .reason = "Session expired",
                };
            }
        } else {
            return .{
                .allowed = false,
                .reason = "No active session",
            };
        }

        // Check single transaction limit
        if (amount > self.config.max_single_tx_amount) {
            return .{
                .allowed = false,
                .reason = "Amount exceeds single transaction limit",
            };
        }

        // Check session limit
        if (session) |s| {
            if (s.session_spent + amount > self.config.max_session_amount) {
                return .{
                    .allowed = false,
                    .reason = "Amount exceeds session limit",
                };
            }
        }

        // Check daily limit
        if (!self.daily_tracker.isToday()) {
            self.daily_tracker.reset();
        }
        if (self.daily_tracker.total_spent + amount > self.config.daily_limit) {
            return .{
                .allowed = false,
                .reason = "Amount exceeds daily limit",
            };
        }

        // Check allowed recipients
        if (self.config.allowed_recipients.len > 0) {
            var allowed = false;
            for (self.config.allowed_recipients) |addr| {
                if (std.mem.eql(u8, addr, recipient)) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) {
                return .{
                    .allowed = false,
                    .reason = "Recipient not in allowlist",
                };
            }
        }

        // Check blocked recipients
        for (self.config.blocked_recipients) |addr| {
            if (std.mem.eql(u8, addr, recipient)) {
                return .{
                    .allowed = false,
                    .reason = "Recipient is blocked",
                };
            }
        }

        // Determine if confirmation is needed
        const requires_confirmation = amount >= self.config.confirmation_threshold;
        const requires_auth = amount >= self.config.require_auth_threshold;

        return .{
            .allowed = true,
            .requires_confirmation = requires_confirmation,
            .requires_auth = requires_auth,
        };
    }

    /// Record successful transaction
    pub fn recordTransaction(self: *PolicyEngine, session: *Session, amount: u64) void {
        session.recordTransaction(amount);
        self.daily_tracker.record(amount);
    }

    /// Get remaining daily limit
    pub fn remainingDailyLimit(self: *const PolicyEngine) u64 {
        if (self.daily_tracker.total_spent >= self.config.daily_limit) {
            return 0;
        }
        return self.config.daily_limit - self.daily_tracker.total_spent;
    }
};

/// Session manager
pub const SessionManager = struct {
    allocator: Allocator,
    sessions: std.ArrayListUnmanaged(Session) = .{},

    pub fn init(allocator: Allocator) SessionManager {
        return .{
            .allocator = allocator,
            .sessions = .{},
        };
    }

    pub fn deinit(self: *SessionManager) void {
        for (self.sessions.items) |*session| {
            session.destroy();
        }
        self.sessions.deinit(self.allocator);
    }

    /// Create new session
    pub fn createSession(
        self: *SessionManager,
        address: []const u8,
        duration_secs: u64,
        auth_method: Session.AuthMethod,
    ) !*Session {
        const session = try Session.create(
            self.allocator,
            address,
            duration_secs,
            auth_method,
        );
        try self.sessions.append(self.allocator, session);
        return &self.sessions.items[self.sessions.items.len - 1];
    }

    /// Get active session for address
    pub fn getActiveSession(self: *SessionManager, address: []const u8) ?*Session {
        for (self.sessions.items) |*session| {
            if (session.isValid() and std.mem.eql(u8, session.address, address)) {
                return session;
            }
        }
        return null;
    }

    /// Invalidate all sessions for address
    pub fn invalidateSessions(self: *SessionManager, address: []const u8) void {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.address, address)) {
                session.active = false;
            }
        }
    }

    /// Clean up expired sessions
    pub fn cleanupExpired(self: *SessionManager) void {
        var i: usize = 0;
        while (i < self.sessions.items.len) {
            if (!self.sessions.items[i].isValid()) {
                self.sessions.items[i].destroy();
                _ = self.sessions.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get session count
    pub fn sessionCount(self: *const SessionManager) usize {
        return self.sessions.items.len;
    }

    /// Get active session count
    pub fn activeSessionCount(self: *const SessionManager) usize {
        var count: usize = 0;
        for (self.sessions.items) |*session| {
            if (session.isValid()) count += 1;
        }
        return count;
    }
};

// Tests
test "Session creation and validation" {
    const allocator = std.testing.allocator;

    const session = try Session.create(
        allocator,
        "0x1234567890abcdef",
        3600,
        .password,
    );
    defer session.destroy();

    try std.testing.expect(session.isValid());
    try std.testing.expectEqualStrings("0x1234567890abcdef", session.address);
    try std.testing.expect(session.remainingSecs() > 0);
}

test "Policy engine transaction checks" {
    const config = WalletConfig{
        .max_single_tx_amount = 1000,
        .max_session_amount = 5000,
        .daily_limit = 10000,
    };

    var engine = PolicyEngine.init(config);
    var session = try Session.create(
        std.testing.allocator,
        "0x1234",
        3600,
        .password,
    );
    defer session.destroy();

    // Valid transaction
    const result1 = engine.checkTransaction(&session, "0x5678", 500);
    try std.testing.expect(result1.allowed);
    try std.testing.expect(!result1.requires_confirmation);

    // Exceeds single tx limit
    const result2 = engine.checkTransaction(&session, "0x5678", 1500);
    try std.testing.expect(!result2.allowed);
}

test "Session manager" {
    const allocator = std.testing.allocator;
    var manager = SessionManager.init(allocator);
    defer manager.deinit();

    const session = try manager.createSession("0x1234", 3600, .password);
    try std.testing.expect(session.isValid());

    const found = manager.getActiveSession("0x1234");
    try std.testing.expect(found != null);
}
