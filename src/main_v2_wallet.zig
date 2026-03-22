// main_v2_wallet.zig - Advanced wallet commands
// Session management and policy enforcement

const std = @import("std");
const Allocator = std.mem.Allocator;
const wallet = @import("wallet/root.zig");

const Wallet = wallet.Wallet;
const WalletConfig = wallet.WalletConfig;
const Session = wallet.Session;

/// Global wallet instance (simplified for demo)
var g_wallet: ?Wallet = null;

pub fn cmdWallet(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printUsage();
        return;
    }

    const action = args[0];

    if (std.mem.eql(u8, action, "init")) {
        try cmdWalletInit(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "session")) {
        try cmdWalletSession(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "status")) {
        try cmdWalletStatus(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "policy")) {
        try cmdWalletPolicy(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "check")) {
        try cmdWalletCheck(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "config")) {
        try cmdWalletConfig(allocator, args[1..]);
    } else {
        std.log.err("Unknown wallet action: {s}", .{action});
        printUsage();
    }
}

fn printUsage() void {
    std.log.info("Usage: wallet <action> [options]", .{});
    std.log.info("", .{});
    std.log.info("Actions:", .{});
    std.log.info("  init <address>              Initialize wallet for address", .{});
    std.log.info("  session start               Start new session", .{});
    std.log.info("  session end                 End current session", .{});
    std.log.info("  status                      Show wallet status", .{});
    std.log.info("  policy                      Show current policy", .{});
    std.log.info("  check <recipient> <amount>  Check if transaction allowed", .{});
    std.log.info("  config                      Show wallet configuration", .{});
    std.log.info("", .{});
    std.log.info("Examples:", .{});
    std.log.info("  wallet init 0x1234...       Initialize wallet", .{});
    std.log.info("  wallet session start        Start session (1 hour)", .{});
    std.log.info("  wallet check 0x5678 1000000 Check if 0.001 SUI tx allowed", .{});
}

fn cmdWalletInit(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: wallet init <address>", .{});
        return;
    }

    const address = args[0];

    // Cleanup existing wallet
    if (g_wallet) |*w| {
        w.deinit();
        g_wallet = null;
    }

    // Default configuration
    const config = WalletConfig{
        .max_session_amount = 100_000_000_000, // 100 SUI
        .max_single_tx_amount = 10_000_000_000, // 10 SUI
        .session_duration_secs = 3600, // 1 hour
        .confirmation_threshold = 1_000_000_000, // 1 SUI
        .daily_limit = 500_000_000_000, // 500 SUI
        .require_auth_threshold = 5_000_000_000, // 5 SUI
    };

    g_wallet = try Wallet.init(allocator, address, config);

    std.log.info("=== Wallet Initialized ===", .{});
    std.log.info("", .{});
    std.log.info("Address: {s}", .{address});
    std.log.info("", .{});
    std.log.info("Policy Configuration:", .{});
    std.log.info("  Max single tx: {d} MIST ({d:.2} SUI)", .{
        config.max_single_tx_amount,
        @as(f64, @floatFromInt(config.max_single_tx_amount)) / 1_000_000_000.0,
    });
    std.log.info("  Max session: {d} MIST ({d:.2} SUI)", .{
        config.max_session_amount,
        @as(f64, @floatFromInt(config.max_session_amount)) / 1_000_000_000.0,
    });
    std.log.info("  Daily limit: {d} MIST ({d:.2} SUI)", .{
        config.daily_limit,
        @as(f64, @floatFromInt(config.daily_limit)) / 1_000_000_000.0,
    });
    std.log.info("  Session duration: {d} minutes", .{config.session_duration_secs / 60});
    std.log.info("", .{});
    std.log.info("Next step: wallet session start", .{});
}

fn cmdWalletSession(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (g_wallet == null) {
        std.log.err("Wallet not initialized. Run: wallet init <address>", .{});
        return;
    }

    var wallet_ptr = &g_wallet.?;

    if (args.len < 1) {
        std.log.err("Usage: wallet session <start|end>", .{});
        return;
    }

    const subaction = args[0];

    if (std.mem.eql(u8, subaction, "start")) {
        // Check if already has active session
        if (wallet_ptr.session_manager.getActiveSession(wallet_ptr.address)) |_| {
            std.log.info("Session already active", .{});
            return;
        }

        const session = try wallet_ptr.startSession(.password);

        std.log.info("=== Session Started ===", .{});
        std.log.info("", .{});
        // Session ID is 32 bytes, print as hex
        std.log.info("Session ID: {x}", .{session.id});
        std.log.info("Address: {s}", .{session.address});
        std.log.info("Auth Method: {s}", .{@tagName(session.auth_method)});
        std.log.info("Expires: {d} minutes", .{@divTrunc(session.remainingSecs(), 60)});
        std.log.info("", .{});
        std.log.info("You can now perform transactions within policy limits.", .{});

    } else if (std.mem.eql(u8, subaction, "end")) {
        wallet_ptr.session_manager.invalidateSessions(wallet_ptr.address);
        std.log.info("=== Session Ended ===", .{});
        std.log.info("", .{});
        std.log.info("All sessions for this wallet have been invalidated.", .{});
        std.log.info("Run 'wallet session start' to create a new session.", .{});

    } else {
        std.log.err("Unknown session action: {s}", .{subaction});
    }
}

fn cmdWalletStatus(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    if (g_wallet == null) {
        std.log.err("Wallet not initialized. Run: wallet init <address>", .{});
        return;
    }

    const status = g_wallet.?.getStatus();

    std.log.info("=== Wallet Status ===", .{});
    std.log.info("", .{});
    std.log.info("Address: {s}", .{status.address});
    std.log.info("", .{});
    std.log.info("Session:", .{});
    if (status.session_active) {
        std.log.info("  Status: ACTIVE", .{});
        const remaining = status.session_expires - std.time.timestamp();
        std.log.info("  Expires in: {d} minutes", .{@max(0, @divTrunc(remaining, 60))});
        std.log.info("  Spent this session: {d} MIST ({d:.4} SUI)", .{
            status.session_spent,
            @as(f64, @floatFromInt(status.session_spent)) / 1_000_000_000.0,
        });
    } else {
        std.log.info("  Status: INACTIVE", .{});
        std.log.info("  Run 'wallet session start' to activate", .{});
    }
    std.log.info("", .{});
    std.log.info("Daily Spending:", .{});
    std.log.info("  Spent today: {d} MIST ({d:.4} SUI)", .{
        status.daily_spent,
        @as(f64, @floatFromInt(status.daily_spent)) / 1_000_000_000.0,
    });
    std.log.info("  Daily limit: {d} MIST ({d:.2} SUI)", .{
        status.daily_limit,
        @as(f64, @floatFromInt(status.daily_limit)) / 1_000_000_000.0,
    });
    std.log.info("  Remaining: {d} MIST ({d:.4} SUI)", .{
        status.remaining_daily,
        @as(f64, @floatFromInt(status.remaining_daily)) / 1_000_000_000.0,
    });
}

fn cmdWalletPolicy(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    if (g_wallet == null) {
        std.log.err("Wallet not initialized. Run: wallet init <address>", .{});
        return;
    }

    const config = g_wallet.?.policy_engine.config;

    std.log.info("=== Wallet Policy ===", .{});
    std.log.info("", .{});
    std.log.info("Transaction Limits:", .{});
    std.log.info("  Max single transaction: {d} MIST ({d:.2} SUI)", .{
        config.max_single_tx_amount,
        @as(f64, @floatFromInt(config.max_single_tx_amount)) / 1_000_000_000.0,
    });
    std.log.info("  Max per session: {d} MIST ({d:.2} SUI)", .{
        config.max_session_amount,
        @as(f64, @floatFromInt(config.max_session_amount)) / 1_000_000_000.0,
    });
    std.log.info("  Daily limit: {d} MIST ({d:.2} SUI)", .{
        config.daily_limit,
        @as(f64, @floatFromInt(config.daily_limit)) / 1_000_000_000.0,
    });
    std.log.info("", .{});
    std.log.info("Security Settings:", .{});
    std.log.info("  Session duration: {d} minutes", .{config.session_duration_secs / 60});
    std.log.info("  Confirmation threshold: {d} MIST ({d:.2} SUI)", .{
        config.confirmation_threshold,
        @as(f64, @floatFromInt(config.confirmation_threshold)) / 1_000_000_000.0,
    });
    std.log.info("  Auth required above: {d} MIST ({d:.2} SUI)", .{
        config.require_auth_threshold,
        @as(f64, @floatFromInt(config.require_auth_threshold)) / 1_000_000_000.0,
    });
    std.log.info("", .{});
    std.log.info("Allowed Recipients: {s}", .{
        if (config.allowed_recipients.len == 0) "Any (no restrictions)" else "Restricted",
    });
    std.log.info("Blocked Recipients: {d}", .{config.blocked_recipients.len});
}

fn cmdWalletCheck(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (g_wallet == null) {
        std.log.err("Wallet not initialized. Run: wallet init <address>", .{});
        return;
    }

    if (args.len < 2) {
        std.log.err("Usage: wallet check <recipient> <amount_mist>", .{});
        std.log.info("Example: wallet check 0x5678 1000000", .{});
        return;
    }

    const recipient = args[0];
    const amount = try std.fmt.parseInt(u64, args[1], 10);

    const result = g_wallet.?.canTransact(recipient, amount);

    std.log.info("=== Transaction Check ===", .{});
    std.log.info("", .{});
    std.log.info("Recipient: {s}", .{recipient});
    std.log.info("Amount: {d} MIST ({d:.6} SUI)", .{
        amount,
        @as(f64, @floatFromInt(amount)) / 1_000_000_000.0,
    });
    std.log.info("", .{});
    std.log.info("Result:", .{});
    if (result.allowed) {
        std.log.info("  Status: ALLOWED", .{});
        if (result.requires_confirmation) {
            std.log.info("  Confirmation: REQUIRED", .{});
        }
        if (result.requires_auth) {
            std.log.info("  Authentication: REQUIRED", .{});
        }
        if (!result.requires_confirmation and !result.requires_auth) {
            std.log.info("  Confirmation: Not required", .{});
        }
    } else {
        std.log.info("  Status: BLOCKED", .{});
        if (result.reason) |reason| {
            std.log.info("  Reason: {s}", .{reason});
        }
    }
}

fn cmdWalletConfig(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    if (g_wallet == null) {
        std.log.err("Wallet not initialized. Run: wallet init <address>", .{});
        return;
    }

    // Show configuration file path and format
    std.log.info("=== Wallet Configuration ===", .{});
    std.log.info("", .{});
    std.log.info("Configuration is stored in:", .{});
    std.log.info("  ~/.sui/wallet/config.json", .{});
    std.log.info("", .{});
    std.log.info("To modify configuration, edit the JSON file:", .{});
    std.log.info("  {{", .{});
    std.log.info("    \"max_single_tx_amount\": 10000000000,", .{});
    std.log.info("    \"max_session_amount\": 100000000000,", .{});
    std.log.info("    \"daily_limit\": 500000000000,", .{});
    std.log.info("    \"session_duration_secs\": 3600,", .{});
    std.log.info("    \"confirmation_threshold\": 1000000000,", .{});
    std.log.info("    \"require_auth_threshold\": 5000000000", .{});
    std.log.info("  }}", .{});
}
