// Browser WebAuthn Bridge
// Communicates with browser via local HTTP server
// Supports hardware keys (YubiKey) and platform authenticators

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import the server-based implementation
const server_impl = @import("browser_server.zig");
const simple_impl = @import("browser_simple.zig");

/// WebAuthn bridge server (unified interface)
pub const BrowserBridge = struct {
    allocator: Allocator,
    port: u16,
    mode: BridgeMode,

    const BridgeMode = enum {
        server, // Use HTTP server
        simple, // Use file-based approach
    };

    const Self = @This();

    pub fn init(allocator: Allocator, port: u16) Self {
        return Self{
            .allocator = allocator,
            .port = port,
            .mode = .server,
        };
    }

    /// Create credential using the best available method
    pub fn createCredential(
        self: *Self,
        rp_id: []const u8,
        user_name: []const u8,
    ) !Credential {
        return switch (self.mode) {
            .server => self.createCredentialWithServer(rp_id, user_name),
            .simple => self.createCredentialSimple(rp_id, user_name),
        };
    }

    /// Create credential using HTTP server method
    fn createCredentialWithServer(
        self: *Self,
        rp_id: []const u8,
        user_name: []const u8,
    ) !Credential {
        const tmp_dir = try std.fs.path.join(self.allocator, &.{ "/tmp", "sui-webauthn" });
        defer self.allocator.free(tmp_dir);

        return server_impl.createCredentialInBrowser(
            self.allocator,
            rp_id,
            user_name,
            tmp_dir,
        );
    }

    /// Create credential using simple file-based method
    fn createCredentialSimple(
        self: *Self,
        rp_id: []const u8,
        user_name: []const u8,
    ) !Credential {
        const tmp_dir = try std.fs.path.join(self.allocator, &.{ "/tmp", "sui-webauthn-simple" });
        defer self.allocator.free(tmp_dir);

        return simple_impl.createCredentialInBrowser(
            self.allocator,
            rp_id,
            user_name,
            tmp_dir,
        );
    }

    /// Get assertion (sign challenge) using credential
    pub fn getAssertion(
        self: *Self,
        rp_id: []const u8,
        credential_id: []const u8,
        challenge: []const u8,
    ) !Assertion {
        // For now, use the simple file-based approach
        _ = self;
        _ = rp_id;
        _ = credential_id;
        _ = challenge;
        return error.NotImplemented;
    }
};

/// Create WebAuthn credential via browser
/// This is the main entry point for credential creation
pub fn createCredential(
    allocator: Allocator,
    rp_id: []const u8,
    user_name: []const u8,
) !Credential {
    var bridge = BrowserBridge.init(allocator, 8765);
    return bridge.createCredential(rp_id, user_name);
}

/// Get WebAuthn assertion (sign data)
pub fn getAssertion(
    allocator: Allocator,
    rp_id: []const u8,
    credential_id: []const u8,
    challenge: []const u8,
) !Assertion {
    var bridge = BrowserBridge.init(allocator, 8765);
    return bridge.getAssertion(rp_id, credential_id, challenge);
}

/// Re-export types
pub const Credential = server_impl.Credential;
pub const Assertion = struct {
    authenticator_data: []const u8,
    client_data_json: []const u8,
    signature: []const u8,

    pub fn deinit(self: *Assertion, allocator: Allocator) void {
        allocator.free(self.authenticator_data);
        allocator.free(self.client_data_json);
        allocator.free(self.signature);
    }
};

// ============================================================
// Tests
// ============================================================

test "BrowserBridge initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const bridge = BrowserBridge.init(allocator, 8765);
    try testing.expectEqual(@as(u16, 8765), bridge.port);
    try testing.expectEqual(BrowserBridge.BridgeMode.server, bridge.mode);
}

test "Assertion lifecycle" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assertion = Assertion{
        .authenticator_data = try allocator.dupe(u8, "auth_data"),
        .client_data_json = try allocator.dupe(u8, "client_data"),
        .signature = try allocator.dupe(u8, "signature"),
    };
    defer assertion.deinit(allocator);

    try testing.expectEqualStrings("auth_data", assertion.authenticator_data);
    try testing.expectEqualStrings("client_data", assertion.client_data_json);
    try testing.expectEqualStrings("signature", assertion.signature);
}
