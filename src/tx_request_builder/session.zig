/// tx_request_builder/session.zig - Session management for authorization
const std = @import("std");

/// Account session kind
pub const AccountSessionKind = enum {
    none,
    sign_personal_message,
    passkey,
    zklogin,
};

/// Session challenge union
pub const SessionChallenge = union(enum) {
    /// No challenge
    none,
    /// Sign personal message challenge
    sign_personal_message: SignPersonalMessageChallenge,
    /// Passkey challenge
    passkey: PasskeyChallenge,
    /// zkLogin nonce challenge
    zklogin_nonce: ZkLoginNonceChallenge,

    pub fn deinit(self: *SessionChallenge, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .sign_personal_message => |*s| s.deinit(allocator),
            .passkey => |*p| p.deinit(allocator),
            .zklogin_nonce => |*z| z.deinit(allocator),
            .none => {},
        }
    }
};

/// Sign personal message challenge
pub const SignPersonalMessageChallenge = struct {
    /// Message to sign
    message: []const u8,
    /// Expected signer address
    expected_signer: []const u8,
    /// Challenge description
    description: ?[]const u8 = null,

    pub fn deinit(self: *SignPersonalMessageChallenge, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.expected_signer);
        if (self.description) |d| allocator.free(d);
    }
};

/// Passkey challenge
pub const PasskeyChallenge = struct {
    /// Challenge bytes
    challenge: []const u8,
    /// Relying party ID (e.g., domain)
    rp_id: []const u8,
    /// User ID
    user_id: []const u8,
    /// Challenge timeout in milliseconds
    timeout_ms: u32 = 60000,

    pub fn deinit(self: *PasskeyChallenge, allocator: std.mem.Allocator) void {
        allocator.free(self.challenge);
        allocator.free(self.rp_id);
        allocator.free(self.user_id);
    }
};

/// zkLogin nonce challenge
pub const ZkLoginNonceChallenge = struct {
    /// Nonce value
    nonce: []const u8,
    /// Ephemeral public key
    ephemeral_public_key: []const u8,
    /// Expiration time
    expiration: u64,

    pub fn deinit(self: *ZkLoginNonceChallenge, allocator: std.mem.Allocator) void {
        allocator.free(self.nonce);
        allocator.free(self.ephemeral_public_key);
    }
};

/// Session challenge request
pub const SessionChallengeRequest = struct {
    /// Challenge type
    challenge: SessionChallenge,
    /// Account identifier
    account_id: []const u8,
    /// Request timestamp
    timestamp_ms: u64,

    pub fn deinit(self: *SessionChallengeRequest, allocator: std.mem.Allocator) void {
        self.challenge.deinit(allocator);
        allocator.free(self.account_id);
    }
};

/// Session challenge response
pub const SessionChallengeResponse = struct {
    /// Challenge that was completed
    challenge: SessionChallenge,
    /// Response data (signature, proof, etc.)
    response_data: []const u8,
    /// Account identifier
    account_id: []const u8,

    pub fn deinit(self: *SessionChallengeResponse, allocator: std.mem.Allocator) void {
        self.challenge.deinit(allocator);
        allocator.free(self.response_data);
        allocator.free(self.account_id);
    }
};

/// Session challenger interface
pub const SessionChallenger = struct {
    context: *anyopaque,
    create_challenge: *const fn (*anyopaque, []const u8) anyerror!SessionChallenge,
    verify_response: *const fn (*anyopaque, SessionChallengeResponse) anyerror!bool,
};

/// Build challenge text for sign personal message
pub fn buildSignPersonalMessageChallengeText(challenge: SignPersonalMessageChallenge) ![]const u8 {
    var buf: [1024]u8 = undefined;
    if (challenge.description) |desc| {
        return std.fmt.bufPrint(
            &buf,
            "Sign this message to authorize session for {s}: {s}",
            .{ challenge.expected_signer, desc },
        );
    } else {
        return std.fmt.bufPrint(
            &buf,
            "Sign this message to authorize session for {s}",
            .{challenge.expected_signer},
        );
    }
}

/// Build session challenge text for display
pub fn buildSessionChallengeText(challenge: SessionChallenge) !?[]const u8 {
    return switch (challenge) {
        .sign_personal_message => |s| try buildSignPersonalMessageChallengeText(s),
        .passkey => |p| try std.fmt.allocPrint(
            std.heap.page_allocator,
            "Passkey challenge from {s} for user {s}",
            .{ p.rp_id, p.user_id },
        ),
        .zklogin_nonce => |z| try std.fmt.allocPrint(
            std.heap.page_allocator,
            "zkLogin nonce challenge: {s}",
            .{z.nonce},
        ),
        .none => null,
    };
}

// ============================================================
// Tests
// ============================================================

test "SignPersonalMessageChallenge lifecycle" {
    const testing = std.testing;

    var challenge = SignPersonalMessageChallenge{
        .message = try testing.allocator.dupe(u8, "authorize"),
        .expected_signer = try testing.allocator.dupe(u8, "0x123"),
        .description = try testing.allocator.dupe(u8, "test session"),
    };
    defer challenge.deinit(testing.allocator);

    try testing.expectEqualStrings("authorize", challenge.message);
    try testing.expectEqualStrings("0x123", challenge.expected_signer);
}

test "PasskeyChallenge lifecycle" {
    const testing = std.testing;

    var challenge = PasskeyChallenge{
        .challenge = try testing.allocator.dupe(u8, "challenge_bytes"),
        .rp_id = try testing.allocator.dupe(u8, "example.com"),
        .user_id = try testing.allocator.dupe(u8, "user123"),
        .timeout_ms = 30000,
    };
    defer challenge.deinit(testing.allocator);

    try testing.expectEqualStrings("challenge_bytes", challenge.challenge);
    try testing.expectEqual(@as(u32, 30000), challenge.timeout_ms);
}

test "ZkLoginNonceChallenge lifecycle" {
    const testing = std.testing;

    var challenge = ZkLoginNonceChallenge{
        .nonce = try testing.allocator.dupe(u8, "nonce123"),
        .ephemeral_public_key = try testing.allocator.dupe(u8, "epk"),
        .expiration = 1234567890,
    };
    defer challenge.deinit(testing.allocator);

    try testing.expectEqualStrings("nonce123", challenge.nonce);
    try testing.expectEqual(@as(u64, 1234567890), challenge.expiration);
}

test "SessionChallenge lifecycle" {
    const testing = std.testing;

    var challenge = SessionChallenge{
        .sign_personal_message = .{
            .message = try testing.allocator.dupe(u8, "msg"),
            .expected_signer = try testing.allocator.dupe(u8, "0x123"),
        },
    };
    defer challenge.deinit(testing.allocator);

    try testing.expectEqualStrings("msg", challenge.sign_personal_message.message);
}

test "SessionChallengeRequest lifecycle" {
    const testing = std.testing;

    var request = SessionChallengeRequest{
        .challenge = .{ .none = {} },
        .account_id = try testing.allocator.dupe(u8, "account_1"),
        .timestamp_ms = 1234567890,
    };
    defer request.deinit(testing.allocator);

    try testing.expectEqualStrings("account_1", request.account_id);
}

test "SessionChallengeResponse lifecycle" {
    const testing = std.testing;

    var response = SessionChallengeResponse{
        .challenge = .{ .none = {} },
        .response_data = try testing.allocator.dupe(u8, "signature"),
        .account_id = try testing.allocator.dupe(u8, "account_1"),
    };
    defer response.deinit(testing.allocator);

    try testing.expectEqualStrings("signature", response.response_data);
}

test "buildSignPersonalMessageChallengeText with description" {
    const testing = std.testing;

    const challenge = SignPersonalMessageChallenge{
        .message = "authorize",
        .expected_signer = "0x123",
        .description = "test session",
    };

    const text = try buildSignPersonalMessageChallengeText(challenge);
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "0x123"));
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "test session"));
}

test "buildSignPersonalMessageChallengeText without description" {
    const testing = std.testing;

    const challenge = SignPersonalMessageChallenge{
        .message = "authorize",
        .expected_signer = "0x123",
        .description = null,
    };

    const text = try buildSignPersonalMessageChallengeText(challenge);
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "0x123"));
}

test "buildSessionChallengeText with passkey" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = SessionChallenge{
        .passkey = .{
            .challenge = try allocator.dupe(u8, "c"),
            .rp_id = try allocator.dupe(u8, "example.com"),
            .user_id = try allocator.dupe(u8, "user"),
        },
    };
    defer challenge.deinit(allocator);

    const text = try buildSessionChallengeText(challenge);
    defer if (text) |t| allocator.free(t);

    try testing.expect(text != null);
    try testing.expect(std.mem.containsAtLeast(u8, text.?, 1, "Passkey"));
}

test "AccountSessionKind enum" {
    const testing = std.testing;

    const kind = AccountSessionKind.sign_personal_message;
    try testing.expectEqual(AccountSessionKind.sign_personal_message, kind);
}
