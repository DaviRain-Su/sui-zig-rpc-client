/// tx_request_builder/authorization.zig - Authorization planning for transactions
const std = @import("std");
const types = @import("types.zig");
const account = @import("account.zig");
const session = @import("session.zig");

const ProgrammaticRequestOptions = types.ProgrammaticRequestOptions;
const AccountProvider = account.AccountProvider;
const AccountSessionKind = types.AccountSessionKind;
const SessionChallenge = session.SessionChallenge;
const SessionChallengeRequest = session.SessionChallengeRequest;
const SessionChallengeResponse = session.SessionChallengeResponse;

/// Authorization plan for executing transactions
pub const AuthorizationPlan = struct {
    /// Request options
    options: ProgrammaticRequestOptions,
    /// Account provider for signing
    provider: AccountProvider = .{ .none = {} },

    /// Get challenge request if session authorization is needed
    pub fn challengeRequest(self: AuthorizationPlan) ?SessionChallengeRequest {
        return sessionChallengeRequest(self.options, self.provider);
    }

    /// Build challenge text for display
    pub fn challengeText(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
    ) !?[]u8 {
        const req = self.challengeRequest() orelse return null;
        return try session.buildSessionChallengeText(req.challenge);
    }

    /// Create new plan with challenge response applied
    pub fn withChallengeResponse(
        self: AuthorizationPlan,
        response: SessionChallengeResponse,
    ) !AuthorizationPlan {
        return .{
            .options = self.options,
            .provider = try applySessionChallengeResponse(self.provider, response),
        };
    }

    /// Check if plan can execute
    pub fn canExecute(self: AuthorizationPlan) bool {
        return account.accountProviderCanExecute(self.provider);
    }
};

/// Owned authorization plan with memory management
pub const OwnedAuthorizationPlan = struct {
    /// Owned options
    owned_options: OwnedProgrammaticRequestOptions,
    /// Account provider
    provider: AccountProvider = .{ .none = {} },

    /// Deinitialize
    pub fn deinit(self: *OwnedAuthorizationPlan, allocator: std.mem.Allocator) void {
        self.owned_options.deinit(allocator);
        self.provider.deinit(allocator);
    }

    /// Get authorization plan
    pub fn plan(self: *const OwnedAuthorizationPlan) AuthorizationPlan {
        return .{
            .options = self.owned_options.options,
            .provider = self.provider,
        };
    }

    /// Get challenge request
    pub fn challengeRequest(self: *const OwnedAuthorizationPlan) ?SessionChallengeRequest {
        return self.plan().challengeRequest();
    }

    /// Apply challenge response
    pub fn withChallengeResponse(
        self: *OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
        response: SessionChallengeResponse,
    ) !void {
        self.provider = try applySessionChallengeResponse(self.provider, response);
    }
};

/// Owned programmatic request options
pub const OwnedProgrammaticRequestOptions = struct {
    /// Options
    options: ProgrammaticRequestOptions,
    /// Owned strings
    owned_alias: ?[]u8 = null,
    owned_sender: ?[]u8 = null,

    /// Deinitialize
    pub fn deinit(self: *OwnedProgrammaticRequestOptions, allocator: std.mem.Allocator) void {
        if (self.owned_alias) |v| allocator.free(v);
        if (self.owned_sender) |v| allocator.free(v);
        self.options.deinit(allocator);
    }
};

/// Create authorization plan
pub fn authorizationPlan(
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) AuthorizationPlan {
    return .{
        .options = options,
        .provider = provider,
    };
}

/// Create owned authorization plan
pub fn ownedAuthorizationPlan(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) !OwnedAuthorizationPlan {
    var owned = OwnedProgrammaticRequestOptions{
        .options = options,
    };
    errdefer owned.deinit(allocator);

    if (options.alias) |a| {
        owned.owned_alias = try allocator.dupe(u8, a);
        owned.options.alias = owned.owned_alias;
    }

    if (options.sender) |s| {
        owned.owned_sender = try allocator.dupe(u8, s);
        owned.options.sender = owned.owned_sender;
    }

    return .{
        .owned_options = owned,
        .provider = provider,
    };
}

/// Get session challenge request for provider
fn sessionChallengeRequest(
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) ?SessionChallengeRequest {
    _ = options;
    return switch (provider) {
        .future_wallet => |fw| if (fw.session_challenge != null)
            SessionChallengeRequest{
                .challenge = .{ .none = {} },
                .account_id = fw.id,
                .timestamp_ms = @intCast(std.time.milliTimestamp()),
            }
        else
            null,
        else => null,
    };
}

/// Apply session challenge response to provider
fn applySessionChallengeResponse(
    provider: AccountProvider,
    response: SessionChallengeResponse,
) !AccountProvider {
    var new_provider = provider;
    switch (new_provider) {
        .future_wallet => |*fw| {
            if (fw.session_challenge) |c| {
                std.heap.page_allocator.free(c);
            }
            fw.session_challenge = try std.heap.page_allocator.dupe(u8, response.response_data);
        },
        else => {},
    }
    return new_provider;
}

// ============================================================
// Tests
// ============================================================

test "AuthorizationPlan basic" {
    const testing = std.testing;

    const plan = AuthorizationPlan{
        .options = .{},
        .provider = .{ .none = {} },
    };

    try testing.expect(!plan.canExecute());
}

test "AuthorizationPlan with direct provider" {
    const testing = std.testing;

    const plan = AuthorizationPlan{
        .options = .{},
        .provider = .{
            .direct = .{
                .private_key = "key",
                .address = "0x123",
                .key_scheme = "ed25519",
            },
        },
    };

    try testing.expect(plan.canExecute());
}

test "OwnedAuthorizationPlan lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = ProgrammaticRequestOptions{
        .alias = try allocator.dupe(u8, "test_alias"),
        .gas_budget = 1000000,
    };

    var owned = try ownedAuthorizationPlan(allocator, options, .{ .none = {} });
    defer owned.deinit(allocator);

    const plan = owned.plan();
    try testing.expectEqual(@as(?u64, 1000000), plan.options.gas_budget);
}

test "OwnedProgrammaticRequestOptions lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var owned = OwnedProgrammaticRequestOptions{
        .options = .{
            .alias = try allocator.dupe(u8, "alias"),
            .sender = try allocator.dupe(u8, "0x123"),
        },
    };
    owned.owned_alias = owned.options.alias.?;
    owned.owned_sender = owned.options.sender.?;

    defer owned.deinit(allocator);

    try testing.expectEqualStrings("alias", owned.options.alias.?);
}

test "authorizationPlan function" {
    const testing = std.testing;

    const options = ProgrammaticRequestOptions{ .gas_budget = 50000 };
    const provider = AccountProvider{ .none = {} };

    const plan = authorizationPlan(options, provider);

    try testing.expectEqual(@as(?u64, 50000), plan.options.gas_budget);
}

test "sessionChallengeRequest with future wallet" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = ProgrammaticRequestOptions{};
    const provider = AccountProvider{
        .future_wallet = .{
            .id = try allocator.dupe(u8, "wallet_1"),
            .wallet_type = try allocator.dupe(u8, "passkey"),
            .session_challenge = try allocator.dupe(u8, "challenge"),
        },
    };
    defer provider.deinit(allocator);

    const request = sessionChallengeRequest(options, provider);
    try testing.expect(request != null);
}

test "applySessionChallengeResponse" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const provider = AccountProvider{
        .future_wallet = .{
            .id = try allocator.dupe(u8, "wallet_1"),
            .wallet_type = try allocator.dupe(u8, "passkey"),
            .session_challenge = null,
        },
    };
    defer provider.deinit(allocator);

    const response = SessionChallengeResponse{
        .challenge = .{ .none = {} },
        .response_data = try allocator.dupe(u8, "signature"),
        .account_id = try allocator.dupe(u8, "wallet_1"),
    };
    defer response.deinit(allocator);

    const new_provider = try applySessionChallengeResponse(provider, response);
    defer new_provider.deinit(allocator);

    try testing.expect(new_provider.future_wallet.session_challenge != null);
}

test "AuthorizationPlan challengeText" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const plan = AuthorizationPlan{
        .options = .{},
        .provider = .{ .none = {} },
    };

    const text = try plan.challengeText(allocator);
    defer if (text) |t| allocator.free(t);

    try testing.expect(text == null);
}

test "OwnedAuthorizationPlan withChallengeResponse" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = ProgrammaticRequestOptions{};
    const provider = AccountProvider{
        .future_wallet = .{
            .id = try allocator.dupe(u8, "wallet_1"),
            .wallet_type = try allocator.dupe(u8, "passkey"),
            .session_challenge = null,
        },
    };

    var owned = try ownedAuthorizationPlan(allocator, options, provider);
    defer owned.deinit(allocator);

    const response = SessionChallengeResponse{
        .challenge = .{ .none = {} },
        .response_data = try allocator.dupe(u8, "signature"),
        .account_id = try allocator.dupe(u8, "wallet_1"),
    };
    defer response.deinit(allocator);

    try owned.withChallengeResponse(allocator, response);

    try testing.expect(owned.provider.future_wallet.session_challenge != null);
}
