/// macOS WebAuthn Implementation using Objective-C bindings
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import C bindings
const c = @cImport({
    @cInclude("webauthn/macos_bridge.h");
});

pub const MacOSWebAuthn = struct {
    allocator: Allocator,
    context: c.LAContextRef,

    pub fn init(allocator: Allocator) !MacOSWebAuthn {
        const context = c.LAContextCreate();
        if (context == null) {
            return error.FailedToCreateContext;
        }

        return .{
            .allocator = allocator,
            .context = context,
        };
    }

    pub fn deinit(self: *MacOSWebAuthn) void {
        if (self.context != null) {
            c.LAContextRelease(self.context);
            self.context = null;
        }
    }

    /// Check if biometric authentication is available
    pub fn isBiometricAvailable(self: *const MacOSWebAuthn) bool {
        var errorCode: i32 = 0;
        return c.LAContextCanEvaluatePolicy(
            self.context,
            c.POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
            &errorCode,
        );
    }

    /// Get the type of biometric sensor
    pub fn getBiometryType(self: *const MacOSWebAuthn) BiometryType {
        const bioType = c.LAContextGetBiometryType(self.context);
        return switch (bioType) {
            c.BIOMETRY_TYPE_TOUCH_ID => .touch_id,
            c.BIOMETRY_TYPE_FACE_ID => .face_id,
            c.BIOMETRY_TYPE_OPTIC_ID => .optic_id,
            else => .none,
        };
    }

    /// Request biometric authentication
    pub fn authenticate(self: *const MacOSWebAuthn, reason: []const u8) !void {
        const reasonC = try self.allocator.dupeZ(u8, reason);
        defer self.allocator.free(reasonC);

        // Create completion handler
        var completed = false;
        var success = false;
        var errorCode: i32 = 0;

        const CompletionHandler = struct {
            completed: *bool,
            success: *bool,
            errorCode: *i32,

            pub fn callback(s: bool, err: i32, ctx: *@This()) void {
                ctx.success.* = s;
                ctx.errorCode.* = err;
                ctx.completed.* = true;
            }
        };

        var handler = CompletionHandler{
            .completed = &completed,
            .success = &success,
            .errorCode = &errorCode,
        };

        // Start authentication
        c.LAContextEvaluatePolicy(
            self.context,
            c.POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
            reasonC.ptr,
            @ptrCast(&CompletionHandler.callback),
            &handler,
        );

        // Wait for completion (in real app, use async)
        var attempts: u32 = 0;
        while (!completed and attempts < 300) { // 30 second timeout
            std.time.sleep(100 * std.time.ns_per_ms);
            attempts += 1;
        }

        if (!completed) {
            return error.AuthenticationTimeout;
        }

        if (!success) {
            return switch (errorCode) {
                c.LA_ERROR_USER_CANCEL => error.UserCancelled,
                c.LA_ERROR_BIOMETRY_NOT_AVAILABLE => error.BiometryNotAvailable,
                c.LA_ERROR_BIOMETRY_NOT_ENROLLED => error.BiometryNotEnrolled,
                c.LA_ERROR_BIOMETRY_LOCKOUT => error.BiometryLockout,
                else => error.AuthenticationFailed,
            };
        }
    }

    /// Create a new credential in Secure Enclave
    pub fn createCredential(self: *const MacOSWebAuthn, tag: []const u8) !Credential {
        const tagZ = try self.allocator.dupeZ(u8, tag);
        defer self.allocator.free(tagZ);

        var errorCode: i32 = 0;
        const privateKey = c.SecKeyGenerateSecureEnclaveKey(
            tagZ.ptr,
            true, // Require biometric
            &errorCode,
        );

        if (privateKey == null) {
            return switch (errorCode) {
                c.LA_ERROR_BIOMETRY_NOT_AVAILABLE => error.BiometryNotAvailable,
                c.LA_ERROR_BIOMETRY_NOT_ENROLLED => error.BiometryNotEnrolled,
                else => error.KeyGenerationFailed,
            };
        }
        defer c.SecKeyRelease(privateKey);

        // Get public key
        const publicKey = c.SecKeyCopyPublicKey(privateKey);
        if (publicKey == null) {
            return error.FailedToGetPublicKey;
        }
        defer c.SecKeyRelease(publicKey);

        // Export public key
        var exportError: i32 = 0;
        const publicKeyData = c.SecKeyCopyExternalRepresentation(publicKey, &exportError);
        if (publicKeyData == null) {
            return error.FailedToExportPublicKey;
        }
        defer c.NSDataRelease(publicKeyData);

        const keyLength = c.NSDataGetLength(publicKeyData);
        const keyBytes = c.NSDataGetBytes(publicKeyData);

        // Copy public key
        const publicKeyCopy = try self.allocator.dupe(u8, keyBytes[0..keyLength]);

        return .{
            .tag = try self.allocator.dupe(u8, tag),
            .public_key = publicKeyCopy,
        };
    }

    /// Sign data with a credential
    pub fn sign(self: *const MacOSWebAuthn, tag: []const u8, data: []const u8) ![]const u8 {
        const tagZ = try self.allocator.dupeZ(u8, tag);
        defer self.allocator.free(tagZ);

        // Load private key from keychain
        var errorCode: i32 = 0;
        const privateKey = c.LoadCredentialFromKeychain(tagZ.ptr, &errorCode);
        if (privateKey == null) {
            return error.CredentialNotFound;
        }
        defer c.SecKeyRelease(privateKey);

        // Sign data
        var signError: i32 = 0;
        const signature = c.SecKeyCreateSignature(
            privateKey,
            data.ptr,
            data.len,
            &signError,
        );

        if (signature == null) {
            return switch (signError) {
                c.LA_ERROR_USER_CANCEL => error.UserCancelled,
                else => error.SigningFailed,
            };
        }
        defer c.NSDataRelease(signature);

        const sigLength = c.NSDataGetLength(signature);
        const sigBytes = c.NSDataGetBytes(signature);

        return try self.allocator.dupe(u8, sigBytes[0..sigLength]);
    }

    /// Delete a credential from keychain
    pub fn deleteCredential(self: *const MacOSWebAuthn, tag: []const u8) !void {
        const tagZ = try self.allocator.dupeZ(u8, tag);
        defer self.allocator.free(tagZ);

        var errorCode: i32 = 0;
        const success = c.DeleteCredentialFromKeychain(tagZ.ptr, &errorCode);

        if (!success) {
            return error.DeletionFailed;
        }
    }

    /// Get human-readable error message
    pub fn getErrorMessage(errorCode: i32) []const u8 {
        const msg = c.GetErrorMessage(errorCode);
        defer c.FreeString(msg);
        return std.mem.span(msg);
    }
};

pub const BiometryType = enum {
    none,
    touch_id,
    face_id,
    optic_id,
};

pub const Credential = struct {
    tag: []const u8,
    public_key: []const u8,

    pub fn deinit(self: *Credential, allocator: Allocator) void {
        allocator.free(self.tag);
        allocator.free(self.public_key);
    }

    /// Derive Sui address from public key
    pub fn deriveAddress(self: *const Credential, allocator: Allocator) ![]const u8 {
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

// Error types
pub const WebAuthnError = error{
    FailedToCreateContext,
    AuthenticationTimeout,
    UserCancelled,
    BiometryNotAvailable,
    BiometryNotEnrolled,
    BiometryLockout,
    AuthenticationFailed,
    KeyGenerationFailed,
    FailedToGetPublicKey,
    FailedToExportPublicKey,
    CredentialNotFound,
    SigningFailed,
    DeletionFailed,
};

// Tests
// Note: These would only work on macOS with the actual framework
test "BiometryType detection" {
    // This is a compile-time test
    const touchId = BiometryType.touch_id;
    _ = touchId;
}
