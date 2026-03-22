/// WebAuthn Platform Abstraction Layer
/// Supports macOS (LocalAuthentication) and Linux (libfido2)
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Platform = enum {
    macos,
    linux,
    unsupported,

    pub fn current() Platform {
        const os_tag = @import("builtin").target.os.tag;
        if (os_tag == .macos or os_tag == .ios) {
            return .macos;
        } else if (os_tag == .linux) {
            return .linux;
        } else {
            return .unsupported;
        }
    }
};

/// WebAuthn Credential Info
pub const CredentialInfo = struct {
    id: []const u8,
    public_key: []const u8,
    sign_count: u32,
};

/// WebAuthn Assertion Result
pub const AssertionResult = struct {
    authenticator_data: []const u8,
    client_data_json: []const u8,
    signature: []const u8,
    user_handle: ?[]const u8,
};

/// Platform-specific WebAuthn implementation
pub const WebAuthnPlatform = union(Platform) {
    macos: MacOSWebAuthnPlaceholder,
    linux: LinuxWebAuthnPlaceholder,
    unsupported: UnsupportedWebAuthn,

    pub fn init(allocator: Allocator) !WebAuthnPlatform {
        return switch (Platform.current()) {
            .macos => .{ .macos = try MacOSWebAuthnPlaceholder.init(allocator) },
            .linux => .{ .linux = try LinuxWebAuthnPlaceholder.init(allocator) },
            .unsupported => .{ .unsupported = UnsupportedWebAuthn.init() },
        };
    }

    pub fn deinit(self: *WebAuthnPlatform) void {
        switch (self.*) {
            .macos => |*m| m.deinit(),
            .linux => |*l| l.deinit(),
            .unsupported => {},
        }
    }

    pub fn isAvailable(self: *const WebAuthnPlatform) bool {
        return switch (self.*) {
            .macos => |*m| m.isAvailable(),
            .linux => |*l| l.isAvailable(),
            .unsupported => false,
        };
    }

    pub fn createCredential(
        self: *WebAuthnPlatform,
        rp_id: []const u8,
        user_name: []const u8,
        user_display_name: []const u8,
    ) !CredentialInfo {
        return switch (self.*) {
            .macos => |*m| try m.createCredential(rp_id, user_name, user_display_name),
            .linux => |*l| try l.createCredential(rp_id, user_name, user_display_name),
            .unsupported => error.PlatformNotSupported,
        };
    }

    pub fn getAssertion(
        self: *WebAuthnPlatform,
        rp_id: []const u8,
        challenge: []const u8,
        credential_id: ?[]const u8,
    ) !AssertionResult {
        return switch (self.*) {
            .macos => |*m| try m.getAssertion(rp_id, challenge, credential_id),
            .linux => |*l| try l.getAssertion(rp_id, challenge, credential_id),
            .unsupported => error.PlatformNotSupported,
        };
    }
};

// ============================================================================
// macOS Implementation (LocalAuthentication + Secure Enclave)
// ============================================================================

/// macOS WebAuthn Placeholder Implementation
///
/// NOTE: This is a placeholder implementation. The actual implementation
/// is in macos_impl.zig and requires:
/// - macOS 10.15+ with LocalAuthentication framework
/// - Secure Enclave support for key generation
/// - Proper entitlements for Touch ID access
///
/// When building with WebAuthn support (-Dwebauthn), the real implementation
/// from macos_impl.zig is used instead of this placeholder.
const MacOSWebAuthnPlaceholder = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) !MacOSWebAuthnPlaceholder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MacOSWebAuthnPlaceholder) void {
        _ = self;
    }

    pub fn isAvailable(self: *const MacOSWebAuthnPlaceholder) bool {
        _ = self;
        // Placeholder: Actual implementation checks Touch ID availability
        return true;
    }

    /// Create credential - NOT IMPLEMENTED in placeholder
    /// Use macos_impl.zig for actual implementation
    pub fn createCredential(
        self: *MacOSWebAuthnPlaceholder,
        rp_id: []const u8,
        user_name: []const u8,
        user_display_name: []const u8,
    ) !CredentialInfo {
        _ = self;
        _ = rp_id;
        _ = user_name;
        _ = user_display_name;
        // Placeholder: Real implementation in macos_impl.zig requires:
        // - LAContext for biometric authentication
        // - Secure Enclave key generation
        // - Keychain storage for credentials
        return error.NotImplemented;
    }

    /// Get assertion - NOT IMPLEMENTED in placeholder
    /// Use macos_impl.zig for actual implementation
    pub fn getAssertion(
        self: *MacOSWebAuthnPlaceholder,
        rp_id: []const u8,
        challenge: []const u8,
        credential_id: ?[]const u8,
    ) !AssertionResult {
        _ = self;
        _ = rp_id;
        _ = challenge;
        _ = credential_id;
        // Placeholder: Real implementation in macos_impl.zig requires:
        // - LAContext for biometric authentication
        // - Secure Enclave key signing
        return error.NotImplemented;
    }
};

/// Linux WebAuthn Placeholder Implementation
///
/// NOTE: This is a placeholder implementation. The actual implementation
/// is in linux.zig and requires:
/// - libfido2 library installed
/// - USB HID device access (/dev/hidraw*)
/// - udev rules for FIDO2 devices
///
/// When building with WebAuthn support on Linux, the real implementation
/// from linux.zig is used instead of this placeholder.
const LinuxWebAuthnPlaceholder = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) !LinuxWebAuthnPlaceholder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LinuxWebAuthnPlaceholder) void {
        _ = self;
    }

    pub fn isAvailable(self: *const LinuxWebAuthnPlaceholder) bool {
        _ = self;
        // Placeholder: Actual implementation checks for libfido2 and devices
        return false;
    }

    /// Create credential - NOT IMPLEMENTED in placeholder
    /// Use linux.zig for actual implementation
    pub fn createCredential(
        self: *LinuxWebAuthnPlaceholder,
        rp_id: []const u8,
        user_name: []const u8,
        user_display_name: []const u8,
    ) !CredentialInfo {
        _ = self;
        _ = rp_id;
        _ = user_name;
        _ = user_display_name;
        // Placeholder: Real implementation in linux.zig requires:
        // - libfido2-dev package
        // - FIDO2/CTAP2 compatible hardware key
        // - USB HID communication
        return error.NotImplemented;
    }

    /// Get assertion - NOT IMPLEMENTED in placeholder
    /// Use linux.zig for actual implementation
    pub fn getAssertion(
        self: *LinuxWebAuthnPlaceholder,
        rp_id: []const u8,
        challenge: []const u8,
        credential_id: ?[]const u8,
    ) !AssertionResult {
        _ = self;
        _ = rp_id;
        _ = challenge;
        _ = credential_id;
        // Placeholder: Real implementation in linux.zig requires:
        // - libfido2 for device communication
        // - User presence verification on hardware key
        return error.NotImplemented;
    }
};

// ============================================================================
// Unsupported Platform
// ============================================================================

const UnsupportedWebAuthn = struct {
    pub fn init() UnsupportedWebAuthn {
        return .{};
    }
};

// Re-export platform implementations
pub const MacOSWebAuthn = @import("macos_impl.zig").MacOSWebAuthn;
pub const BiometryType = @import("macos_impl.zig").BiometryType;
pub const Credential = @import("macos_impl.zig").Credential;

// Linux implementation (libfido2)
pub const LinuxWebAuthn = @import("linux.zig").LinuxWebAuthn;
pub const LinuxCredential = @import("linux.zig").Credential;
pub const LinuxSignature = @import("linux.zig").Signature;
pub const LinuxDeviceInfo = @import("linux.zig").DeviceInfo;
