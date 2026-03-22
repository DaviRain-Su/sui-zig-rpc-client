// macOS WebAuthn Implementation
// Uses Objective-C bridge for LocalAuthentication and Secure Enclave

const std = @import("std");
const builtin = @import("builtin");

// Only compile on macOS
const is_macos = builtin.os.tag == .macos;

// Import C bridge on macOS
const c = if (is_macos) @import("c_bridge.zig") else struct {};

// WebAuthn types
const Credential = @import("platform.zig").Credential;
const CredentialOptions = @import("platform.zig").CredentialOptions;
const SignOptions = @import("platform.zig").SignOptions;
const PlatformError = @import("platform.zig").PlatformError;

/// macOS WebAuthn implementation using Objective-C bridge
pub const MacOSWebAuthnImpl = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    /// Check if WebAuthn is available on this device
    pub fn isAvailable(self: *Self) bool {
        _ = self;
        
        if (!is_macos) return false;
        
        // Create LAContext to check availability
        const context = c.LAContextCreate();
        if (context == null) return false;
        defer c.LAContextRelease(context);
        
        var error_code: c_int = 0;
        return c.LAContextCanEvaluatePolicy(
            context,
            c.BridgeLAPolicy.device_owner_authentication_with_biometrics,
            &error_code
        );
    }
    
    /// Get the type of biometry available
    pub fn getBiometryType(self: *Self) ![]const u8 {
        _ = self;
        
        if (!is_macos) {
            return "none";
        }
        
        const context = c.LAContextCreate();
        if (context == null) return "none";
        defer c.LAContextRelease(context);
        
        const bio_type = c.LAContextGetBiometryType(context);
        return switch (bio_type) {
            .touch_id => "touch_id",
            .face_id => "face_id",
            .optic_id => "optic_id",
            else => "none",
        };
    }
    
    /// Create a new credential using Secure Enclave
    pub fn createCredential(self: *Self, options: CredentialOptions) !Credential {
        if (!is_macos) {
            return PlatformError.NotSupported;
        }
        
        // Generate unique credential ID
        const credential_id = try std.fmt.allocPrint(
            self.allocator,
            "sui-passkey-{s}-{d}",
            .{ options.name, std.time.milliTimestamp() }
        );
        errdefer self.allocator.free(credential_id);
        
        // Generate key in Secure Enclave
        var error_code: c_int = 0;
        const private_key = c.BridgeSecKeyGenerateSecureEnclaveKey(
            credential_id.ptr,
            true, // Require biometric authentication
            &error_code
        );
        
        if (private_key == null) {
            const err_msg = try c.getErrorMessageZig(error_code, self.allocator);
            defer self.allocator.free(err_msg);
            std.log.err("Failed to generate Secure Enclave key: {s}", .{err_msg});
            return PlatformError.KeyGenerationFailed;
        }
        defer c.BridgeSecKeyRelease(private_key);
        
        // Get public key
        const public_key_ref = c.BridgeSecKeyCopyPublicKey(private_key);
        if (public_key_ref == null) {
            return PlatformError.KeyGenerationFailed;
        }
        defer c.BridgeSecKeyRelease(public_key_ref);
        
        // Export public key
        const public_key_data = c.BridgeSecKeyCopyExternalRepresentation(public_key_ref, &error_code);
        if (public_key_data == null) {
            const err_msg = try c.getErrorMessageZig(error_code, self.allocator);
            defer self.allocator.free(err_msg);
            std.log.err("Failed to export public key: {s}", .{err_msg});
            return PlatformError.KeyGenerationFailed;
        }
        defer c.NSDataRelease(public_key_data);
        
        const public_key_bytes = c.nsDataToSlice(public_key_data);
        const public_key = try self.allocator.dupe(u8, public_key_bytes);
        errdefer self.allocator.free(public_key);
        
        // Store credential in keychain
        if (!c.StoreCredentialInKeychain(credential_id.ptr, private_key, &error_code)) {
            const err_msg = try c.getErrorMessageZig(error_code, self.allocator);
            defer self.allocator.free(err_msg);
            std.log.err("Failed to store credential: {s}", .{err_msg});
            return PlatformError.KeychainError;
        }
        
        return Credential{
            .id = credential_id,
            .public_key = public_key,
            .algorithm = "ES256",
            .is_biometric = true,
        };
    }
    
    /// Sign data using a credential
    pub fn sign(self: *Self, options: SignOptions) ![]const u8 {
        if (!is_macos) {
            return PlatformError.NotSupported;
        }
        
        // Load credential from keychain
        var error_code: c_int = 0;
        const private_key = c.LoadCredentialFromKeychain(
            options.credential_id.ptr,
            &error_code
        );
        
        if (private_key == null) {
            const err_msg = try c.getErrorMessageZig(error_code, self.allocator);
            defer self.allocator.free(err_msg);
            std.log.err("Failed to load credential: {s}", .{err_msg});
            return PlatformError.CredentialNotFound;
        }
        defer c.BridgeSecKeyRelease(private_key);
        
        // Sign the data
        const signature_data = c.BridgeSecKeyCreateSignature(
            private_key,
            options.data.ptr,
            options.data.len,
            &error_code
        );
        
        if (signature_data == null) {
            const err_msg = try c.getErrorMessageZig(error_code, self.allocator);
            defer self.allocator.free(err_msg);
            std.log.err("Failed to create signature: {s}", .{err_msg});
            return PlatformError.SigningFailed;
        }
        defer c.NSDataRelease(signature_data);
        
        const signature_bytes = c.nsDataToSlice(signature_data);
        return try self.allocator.dupe(u8, signature_bytes);
    }
    
    /// Delete a credential from the keychain
    pub fn deleteCredential(self: *Self, credential_id: []const u8) !void {
        if (!is_macos) {
            return PlatformError.NotSupported;
        }
        
        var error_code: c_int = 0;
        if (!c.DeleteCredentialFromKeychain(credential_id.ptr, &error_code)) {
            const err_msg = try c.getErrorMessageZig(error_code, self.allocator);
            defer self.allocator.free(err_msg);
            std.log.err("Failed to delete credential: {s}", .{err_msg});
            return PlatformError.KeychainError;
        }
    }
    
    /// List all credentials (returns IDs)
    pub fn listCredentials(self: *Self) ![][]const u8 {
        _ = self;
        // TODO: Implement keychain query to list all credentials
        return &[_][]const u8{};
    }
    
    /// Prompt user for biometric authentication
    pub fn authenticate(self: *Self, reason: []const u8) !bool {
        _ = self;
        
        if (!is_macos) {
            return PlatformError.NotSupported;
        }
        
        const context = c.LAContextCreate();
        if (context == null) return false;
        defer c.LAContextRelease(context);
        
        // Check if we can evaluate
        var error_code: c_int = 0;
        if (!c.LAContextCanEvaluatePolicy(
            context,
            c.BridgeLAPolicy.device_owner_authentication_with_biometrics,
            &error_code
        )) {
            // Fall back to device authentication
            if (!c.LAContextCanEvaluatePolicy(
                context,
                c.BridgeLAPolicy.device_owner_authentication,
                &error_code
            )) {
                return false;
            }
        }
        
        // Create completion handler
        var completed = false;
        var success = false;
        
        const Completion = struct {
            completed: *bool,
            success: *bool,
            
            fn handler(ctx: *@This(), ok: bool, _: c_int) callconv(.C) void {
                ctx.success.* = ok;
                ctx.completed.* = true;
            }
        };
        
        var completion = Completion{
            .completed = &completed,
            .success = &success,
        };
        
        // Evaluate policy
        c.LAContextEvaluatePolicy(
            context,
            c.BridgeLAPolicy.device_owner_authentication_with_biometrics,
            reason.ptr,
            @ptrCast(&Completion.handler),
            &completion
        );
        
        // Wait for completion
        while (!completed) {
            std.time.sleep(10 * std.time.ns_per_ms);
        }
        
        return success;
    }
};

// Export for non-macOS platforms
pub const MacOSWebAuthn = if (is_macos) MacOSWebAuthnImpl else struct {
    pub fn init(allocator: std.mem.Allocator) @This() {
        _ = allocator;
        return .{};
    }
    pub fn deinit(_: *@This()) void {}
    pub fn isAvailable(_: *@This()) bool {
        return false;
    }
    pub fn getBiometryType(_: *@This()) ![]const u8 {
        return "none";
    }
};
