/// WebAuthn Module for Sui
/// Cross-platform Passkey support

const std = @import("std");
const Allocator = std.mem.Allocator;

// Platform-specific implementations
pub const platform = @import("platform.zig");
pub const WebAuthnPlatform = platform.WebAuthnPlatform;
pub const CredentialInfo = platform.CredentialInfo;
pub const AssertionResult = platform.AssertionResult;

// macOS-specific
pub const macos = @import("macos.zig");

// Linux-specific
pub const linux_impl = @import("linux.zig");

/// High-level WebAuthn manager
pub const WebAuthnManager = struct {
    allocator: Allocator,
    platform_impl: WebAuthnPlatform,

    pub fn init(allocator: Allocator) !WebAuthnManager {
        return .{
            .allocator = allocator,
            .platform_impl = try WebAuthnPlatform.init(allocator),
        };
    }

    pub fn deinit(self: *WebAuthnManager) void {
        self.platform_impl.deinit();
    }

    pub fn isAvailable(self: *const WebAuthnManager) bool {
        return self.platform_impl.isAvailable();
    }

    /// Create a new Passkey credential
    pub fn createPasskey(
        self: *WebAuthnManager,
        rp_id: []const u8,
        user_name: []const u8,
    ) !PasskeyCredential {
        const info = try self.platform_impl.createCredential(
            rp_id,
            user_name,
            user_name, // display_name = user_name
        );

        return .{
            .id = try self.allocator.dupe(u8, info.id),
            .public_key = try self.allocator.dupe(u8, info.public_key),
            .rp_id = try self.allocator.dupe(u8, rp_id),
            .user_name = try self.allocator.dupe(u8, user_name),
        };
    }

    /// Sign a Sui transaction with Passkey
    pub fn signTransaction(
        self: *WebAuthnManager,
        credential_id: []const u8,
        tx_hash: [32]u8,
    ) !PasskeySignature {
        // Convert tx_hash to challenge
        const challenge = tx_hash[0..];

        const result = try self.platform_impl.getAssertion(
            "sui.io",
            challenge,
            credential_id,
        );

        return .{
            .authenticator_data = try self.allocator.dupe(u8, result.authenticator_data),
            .client_data_json = try self.allocator.dupe(u8, result.client_data_json),
            .signature = try self.allocator.dupe(u8, result.signature),
        };
    }
};

/// Passkey credential
pub const PasskeyCredential = struct {
    id: []const u8,
    public_key: []const u8,
    rp_id: []const u8,
    user_name: []const u8,

    pub fn deinit(self: *PasskeyCredential, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.public_key);
        allocator.free(self.rp_id);
        allocator.free(self.user_name);
    }

    /// Derive Sui address from public key
    pub fn deriveAddress(self: *const PasskeyCredential, allocator: Allocator) ![]const u8 {
        // Sui address = 0x + hex(first 20 bytes of Blake2b-256(public_key))
        var hash: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(self.public_key, &hash, .{});

        const address = try allocator.alloc(u8, 42);
        address[0] = '0';
        address[1] = 'x';

        const hex_chars = "0123456789abcdef";
        for (hash[0..20], 0..) |byte, i| {
            address[2 + i * 2] = hex_chars[byte >> 4];
            address[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        return address;
    }
};

/// Passkey signature for Sui transaction
pub const PasskeySignature = struct {
    authenticator_data: []const u8,
    client_data_json: []const u8,
    signature: []const u8,

    pub fn deinit(self: *PasskeySignature, allocator: Allocator) void {
        allocator.free(self.authenticator_data);
        allocator.free(self.client_data_json);
        allocator.free(self.signature);
    }

    /// Encode to Sui transaction format
    pub fn toSuiFormat(self: *const PasskeySignature, allocator: Allocator) ![]const u8 {
        // Format: authenticator_data || client_data_json || signature
        const total_len = self.authenticator_data.len +
            self.client_data_json.len +
            self.signature.len;

        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        @memcpy(result[pos..pos + self.authenticator_data.len], self.authenticator_data);
        pos += self.authenticator_data.len;

        @memcpy(result[pos..pos + self.client_data_json.len], self.client_data_json);
        pos += self.client_data_json.len;

        @memcpy(result[pos..pos + self.signature.len], self.signature);

        return result;
    }
};

// Re-export for convenience
pub const Platform = platform.Platform;

// Tests
test "WebAuthnManager initialization" {
    const manager = try WebAuthnManager.init(std.testing.allocator);
    _ = manager.isAvailable();
    manager.deinit();
}
