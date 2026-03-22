/// commands/provider.zig - Programmatic provider functionality
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

const client = @import("sui_client_zig");

/// Provider configuration
pub const ProviderConfig = struct {
    kind: types.CliProviderKind,
    endpoint: ?[]const u8 = null,
    timeout_ms: u64 = 30000,

    pub fn deinit(self: *ProviderConfig, allocator: std.mem.Allocator) void {
        if (self.endpoint) |endpoint| allocator.free(endpoint);
    }
};

/// Session challenge type
pub const SessionChallengeType = enum {
    sign_personal_message,
    passkey,
    zklogin_nonce,
};

/// Session challenge
pub const SessionChallenge = union(SessionChallengeType) {
    sign_personal_message: SignPersonalMessageChallenge,
    passkey: PasskeyChallenge,
    zklogin_nonce: ZkLoginNonceChallenge,

    pub fn deinit(self: *SessionChallenge, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .sign_personal_message => |*c| c.deinit(allocator),
            .passkey => |*c| c.deinit(allocator),
            .zklogin_nonce => |*c| c.deinit(allocator),
        }
    }
};

/// Sign personal message challenge
pub const SignPersonalMessageChallenge = struct {
    domain: []const u8,
    statement: []const u8,
    nonce: []const u8,
    address: ?[]const u8 = null,
    uri: ?[]const u8 = null,
    chain: []const u8 = "sui",
    issued_at_ms: ?u64 = null,
    expires_at_ms: ?u64 = null,
    resources: []const []const u8 = &.{},

    pub fn deinit(self: *SignPersonalMessageChallenge, allocator: std.mem.Allocator) void {
        allocator.free(self.domain);
        allocator.free(self.statement);
        allocator.free(self.nonce);
        if (self.address) |addr| allocator.free(addr);
        if (self.uri) |uri| allocator.free(uri);
        allocator.free(self.chain);
        for (self.resources) |resource| {
            allocator.free(resource);
        }
    }
};

/// Passkey challenge
pub const PasskeyChallenge = struct {
    rp_id: []const u8,
    challenge_b64url: []const u8,
    user_name: ?[]const u8 = null,
    user_display_name: ?[]const u8 = null,
    timeout_ms: ?u64 = null,

    pub fn deinit(self: *PasskeyChallenge, allocator: std.mem.Allocator) void {
        allocator.free(self.rp_id);
        allocator.free(self.challenge_b64url);
        if (self.user_name) |name| allocator.free(name);
        if (self.user_display_name) |name| allocator.free(name);
    }
};

/// ZKLogin nonce challenge
pub const ZkLoginNonceChallenge = struct {
    nonce: []const u8,
    provider: ?[]const u8 = null,
    max_epoch: ?u64 = null,

    pub fn deinit(self: *ZkLoginNonceChallenge, allocator: std.mem.Allocator) void {
        allocator.free(self.nonce);
        if (self.provider) |provider| allocator.free(provider);
    }
};

/// Remote authorization result
pub const RemoteAuthorizationResult = struct {
    sender: ?[]const u8,
    signatures: []const []const u8,
    session: ?AccountSession,
    supports_execute: bool,

    pub fn deinit(self: *RemoteAuthorizationResult, allocator: std.mem.Allocator) void {
        if (self.sender) |s| allocator.free(s);
        for (self.signatures) |sig| allocator.free(sig);
        allocator.free(self.signatures);
        if (self.session) |*s| s.deinit(allocator);
    }
};

/// Account session
pub const AccountSession = struct {
    kind: AccountSessionKind,
    session_id: ?[]const u8,
    user_id: ?[]const u8,
    expires_at_ms: ?u64,

    pub fn deinit(self: *AccountSession, allocator: std.mem.Allocator) void {
        if (self.session_id) |id| allocator.free(id);
        if (self.user_id) |id| allocator.free(id);
    }
};

/// Account session kind
pub const AccountSessionKind = enum {
    none,
    remote_signer,
    passkey,
    zklogin,
    multisig,
};

/// Parse provider kind from string
pub fn parseProviderKind(text: []const u8) !types.CliProviderKind {
    if (std.mem.eql(u8, text, "remote_signer") or std.mem.eql(u8, text, "remoteSigner")) return .remote_signer;
    if (std.mem.eql(u8, text, "passkey")) return .passkey;
    if (std.mem.eql(u8, text, "zklogin") or std.mem.eql(u8, text, "zkLogin")) return .zklogin;
    if (std.mem.eql(u8, text, "multisig")) return .multisig;
    return error.InvalidCli;
}

/// Parse session kind from string
pub fn parseSessionKind(text: []const u8) !AccountSessionKind {
    if (std.mem.eql(u8, text, "none")) return .none;
    if (std.mem.eql(u8, text, "remote_signer")) return .remote_signer;
    if (std.mem.eql(u8, text, "passkey")) return .passkey;
    if (std.mem.eql(u8, text, "zklogin") or std.mem.eql(u8, text, "zkLogin")) return .zklogin;
    if (std.mem.eql(u8, text, "multisig")) return .multisig;
    return error.InvalidCli;
}

/// Build provider config
pub fn buildProviderConfig(
    allocator: std.mem.Allocator,
    kind: types.CliProviderKind,
    endpoint: ?[]const u8,
) !ProviderConfig {
    const endpoint_owned = if (endpoint) |e| try allocator.dupe(u8, e) else null;
    return ProviderConfig{
        .kind = kind,
        .endpoint = endpoint_owned,
    };
}

/// Build sign personal message challenge
pub fn buildSignPersonalMessageChallenge(
    allocator: std.mem.Allocator,
    domain: []const u8,
    statement: []const u8,
    nonce: []const u8,
    address: ?[]const u8,
) !SignPersonalMessageChallenge {
    return SignPersonalMessageChallenge{
        .domain = try allocator.dupe(u8, domain),
        .statement = try allocator.dupe(u8, statement),
        .nonce = try allocator.dupe(u8, nonce),
        .address = if (address) |a| try allocator.dupe(u8, a) else null,
        .chain = try allocator.dupe(u8, "sui"),
        .resources = &.{},
    };
}

/// Build passkey challenge
pub fn buildPasskeyChallenge(
    allocator: std.mem.Allocator,
    rp_id: []const u8,
    challenge_b64url: []const u8,
    user_name: ?[]const u8,
) !PasskeyChallenge {
    return PasskeyChallenge{
        .rp_id = try allocator.dupe(u8, rp_id),
        .challenge_b64url = try allocator.dupe(u8, challenge_b64url),
        .user_name = if (user_name) |n| try allocator.dupe(u8, n) else null,
    };
}

/// Build ZKLogin nonce challenge
pub fn buildZkLoginNonceChallenge(
    allocator: std.mem.Allocator,
    nonce: []const u8,
    provider: ?[]const u8,
    max_epoch: ?u64,
) !ZkLoginNonceChallenge {
    return ZkLoginNonceChallenge{
        .nonce = try allocator.dupe(u8, nonce),
        .provider = if (provider) |p| try allocator.dupe(u8, p) else null,
        .max_epoch = max_epoch,
    };
}

/// Build account session
pub fn buildAccountSession(
    allocator: std.mem.Allocator,
    kind: AccountSessionKind,
    session_id: ?[]const u8,
    user_id: ?[]const u8,
    expires_at_ms: ?u64,
) !AccountSession {
    return AccountSession{
        .kind = kind,
        .session_id = if (session_id) |id| try allocator.dupe(u8, id) else null,
        .user_id = if (user_id) |id| try allocator.dupe(u8, id) else null,
        .expires_at_ms = expires_at_ms,
    };
}

/// Build remote authorization result from JSON
pub fn buildRemoteAuthorizationResultFromJson(
    allocator: std.mem.Allocator,
    json: []const u8,
) !RemoteAuthorizationResult {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const value = parsed.value;
    if (value != .object) return error.InvalidCli;

    const sender = if (value.object.get("sender")) |s|
        if (s == .string) try allocator.dupe(u8, s.string) else null
    else
        null;

    var signatures = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (signatures.items) |sig| allocator.free(sig);
        signatures.deinit();
    }

    if (value.object.get("signatures")) |sigs| {
        if (sigs == .array) {
            for (sigs.array.items) |sig| {
                if (sig == .string) {
                    try signatures.append(try allocator.dupe(u8, sig.string));
                }
            }
        }
    }

    const supports_execute = if (value.object.get("supports_execute")) |se|
        se == .bool and se.bool
    else
        true;

    return RemoteAuthorizationResult{
        .sender = sender,
        .signatures = try signatures.toOwnedSlice(),
        .session = null,
        .supports_execute = supports_execute,
    };
}

/// Format provider config
pub fn formatProviderConfig(
    writer: anytype,
    config: *const ProviderConfig,
) !void {
    try writer.print("Provider: {s}\n", .{@tagName(config.kind)});
    if (config.endpoint) |endpoint| {
        try writer.print("Endpoint: {s}\n", .{endpoint});
    }
    try writer.print("Timeout: {d}ms\n", .{config.timeout_ms});
}

/// Format session challenge
pub fn formatSessionChallenge(
    writer: anytype,
    challenge: *const SessionChallenge,
) !void {
    switch (challenge.*) {
        .sign_personal_message => |c| {
            try writer.print("Sign Personal Message Challenge:\n", .{});
            try writer.print("  Domain: {s}\n", .{c.domain});
            try writer.print("  Statement: {s}\n", .{c.statement});
            try writer.print("  Nonce: {s}\n", .{c.nonce});
            if (c.address) |addr| try writer.print("  Address: {s}\n", .{addr});
        },
        .passkey => |c| {
            try writer.print("Passkey Challenge:\n", .{});
            try writer.print("  RP ID: {s}\n", .{c.rp_id});
            try writer.print("  Challenge: {s}\n", .{c.challenge_b64url});
            if (c.user_name) |name| try writer.print("  User: {s}\n", .{name});
        },
        .zklogin_nonce => |c| {
            try writer.print("ZKLogin Nonce Challenge:\n", .{});
            try writer.print("  Nonce: {s}\n", .{c.nonce});
            if (c.provider) |p| try writer.print("  Provider: {s}\n", .{p});
            if (c.max_epoch) |e| try writer.print("  Max Epoch: {d}\n", .{e});
        },
    }
}

/// Format authorization result
pub fn formatAuthorizationResult(
    writer: anytype,
    result: *const RemoteAuthorizationResult,
) !void {
    if (result.sender) |sender| {
        try writer.print("Sender: {s}\n", .{sender});
    }
    try writer.print("Signatures: {d}\n", .{result.signatures.len});
    for (result.signatures, 0..) |sig, i| {
        try writer.print("  [{d}]: {s}\n", .{ i, sig });
    }
    try writer.print("Supports Execute: {}\n", .{result.supports_execute});
}

// ============================================================
// Tests
// ============================================================

test "parseProviderKind parses valid values" {
    const testing = std.testing;

    try testing.expectEqual(types.CliProviderKind.remote_signer, try parseProviderKind("remote_signer"));
    try testing.expectEqual(types.CliProviderKind.passkey, try parseProviderKind("passkey"));
    try testing.expectEqual(types.CliProviderKind.zklogin, try parseProviderKind("zklogin"));
    try testing.expectEqual(types.CliProviderKind.multisig, try parseProviderKind("multisig"));
}

test "parseProviderKind rejects invalid values" {
    const testing = std.testing;
    try testing.expectError(error.InvalidCli, parseProviderKind("invalid"));
}

test "parseSessionKind parses valid values" {
    const testing = std.testing;

    try testing.expectEqual(AccountSessionKind.none, try parseSessionKind("none"));
    try testing.expectEqual(AccountSessionKind.remote_signer, try parseSessionKind("remote_signer"));
    try testing.expectEqual(AccountSessionKind.passkey, try parseSessionKind("passkey"));
    try testing.expectEqual(AccountSessionKind.zklogin, try parseSessionKind("zklogin"));
    try testing.expectEqual(AccountSessionKind.multisig, try parseSessionKind("multisig"));
}

test "ProviderConfig lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try buildProviderConfig(allocator, .passkey, "https://example.com");
    defer config.deinit(allocator);

    try testing.expectEqual(types.CliProviderKind.passkey, config.kind);
    try testing.expectEqualStrings("https://example.com", config.endpoint.?);
}

test "SignPersonalMessageChallenge lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = try buildSignPersonalMessageChallenge(
        allocator,
        "example.com",
        "Sign in",
        "123",
        "0xabc",
    );
    defer challenge.deinit(allocator);

    try testing.expectEqualStrings("example.com", challenge.domain);
    try testing.expectEqualStrings("Sign in", challenge.statement);
    try testing.expectEqualStrings("123", challenge.nonce);
    try testing.expectEqualStrings("0xabc", challenge.address.?);
}

test "PasskeyChallenge lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = try buildPasskeyChallenge(
        allocator,
        "example.com",
        "challenge123",
        "user123",
    );
    defer challenge.deinit(allocator);

    try testing.expectEqualStrings("example.com", challenge.rp_id);
    try testing.expectEqualStrings("challenge123", challenge.challenge_b64url);
    try testing.expectEqualStrings("user123", challenge.user_name.?);
}

test "ZkLoginNonceChallenge lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = try buildZkLoginNonceChallenge(
        allocator,
        "nonce123",
        "google",
        100,
    );
    defer challenge.deinit(allocator);

    try testing.expectEqualStrings("nonce123", challenge.nonce);
    try testing.expectEqualStrings("google", challenge.provider.?);
    try testing.expectEqual(@as(u64, 100), challenge.max_epoch.?);
}

test "AccountSession lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var session = try buildAccountSession(
        allocator,
        .passkey,
        "session123",
        "user456",
        1234567890,
    );
    defer session.deinit(allocator);

    try testing.expectEqual(AccountSessionKind.passkey, session.kind);
    try testing.expectEqualStrings("session123", session.session_id.?);
    try testing.expectEqualStrings("user456", session.user_id.?);
    try testing.expectEqual(@as(u64, 1234567890), session.expires_at_ms.?);
}

test "SessionChallenge union lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = SessionChallenge{
        .sign_personal_message = try buildSignPersonalMessageChallenge(
            allocator,
            "example.com",
            "Sign in",
            "123",
            null,
        ),
    };
    defer challenge.deinit(allocator);

    try testing.expectEqualStrings("example.com", challenge.sign_personal_message.domain);
}

test "buildRemoteAuthorizationResultFromJson parses valid JSON" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"sender\":\"0x123\",\"signatures\":[\"sig1\",\"sig2\"],\"supports_execute\":true}";

    var result = try buildRemoteAuthorizationResultFromJson(allocator, json);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("0x123", result.sender.?);
    try testing.expectEqual(@as(usize, 2), result.signatures.len);
    try testing.expectEqualStrings("sig1", result.signatures[0]);
    try testing.expect(result.supports_execute);
}

test "formatProviderConfig outputs correctly" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try buildProviderConfig(allocator, .remote_signer, "https://api.example.com");
    defer config.deinit(allocator);

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try formatProviderConfig(output.writer(), &config);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "remote_signer"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "https://api.example.com"));
}

test "formatSessionChallenge outputs sign_personal_message" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = SessionChallenge{
        .sign_personal_message = try buildSignPersonalMessageChallenge(
            allocator,
            "example.com",
            "Sign in",
            "123",
            null,
        ),
    };
    defer challenge.deinit(allocator);

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try formatSessionChallenge(output.writer(), &challenge);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Sign Personal Message Challenge"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "example.com"));
}

test "formatAuthorizationResult outputs correctly" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"sender\":\"0x123\",\"signatures\":[\"sig1\"]}";
    var result = try buildRemoteAuthorizationResultFromJson(allocator, json);
    defer result.deinit(allocator);

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try formatAuthorizationResult(output.writer(), &result);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "0x123"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sig1"));
}
