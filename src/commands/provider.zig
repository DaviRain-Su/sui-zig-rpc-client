/// commands/provider.zig - Programmatic provider functionality
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

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

/// Parse provider kind from string
pub fn parseProviderKind(text: []const u8) !types.CliProviderKind {
    if (std.mem.eql(u8, text, "remote_signer") or std.mem.eql(u8, text, "remoteSigner")) return .remote_signer;
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

test "SignPersonalMessageChallenge deinit" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var challenge = SignPersonalMessageChallenge{
        .domain = try allocator.dupe(u8, "example.com"),
        .statement = try allocator.dupe(u8, "Sign in"),
        .nonce = try allocator.dupe(u8, "123"),
        .address = try allocator.dupe(u8, "0xabc"),
        .chain = try allocator.dupe(u8, "sui"),
    };
    defer challenge.deinit(allocator);

    try testing.expectEqualStrings("example.com", challenge.domain);
}
