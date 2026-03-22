// macOS Keychain-based Passkey implementation
// Uses standard Keychain instead of Secure Enclave
// Supports Touch ID protection for Keychain access

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import C bridge
const c = @import("c_bridge.zig");

// Error types
pub const KeychainError = error{
    KeyGenerationFailed,
    KeyStorageFailed,
    KeyRetrievalFailed,
    KeyDeletionFailed,
    InvalidKeyFormat,
    TouchIDNotAvailable,
};

/// Software key pair stored in Keychain
pub const SoftwareKeyPair = struct {
    tag: []const u8,
    public_key: [32]u8, // Ed25519 public key
    secret_key: [32]u8, // Ed25519 secret key (encrypted in Keychain)
};

/// Generate a new software key pair protected by Keychain
pub fn generateSoftwareKeyPair(
    allocator: Allocator,
    tag: []const u8,
    require_touch_id: bool,
) !SoftwareKeyPair {
    // Generate Ed25519 key pair using Zig's crypto
    const Ed25519 = std.crypto.sign.Ed25519;

    // Generate random seed
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    // Create key pair
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);

    // Store in Keychain
    try storeKeyInKeychain(tag, &seed, require_touch_id);

    return SoftwareKeyPair{
        .tag = try allocator.dupe(u8, tag),
        .public_key = kp.public_key.bytes,
        .secret_key = seed, // Keep seed for now (should encrypt)
    };
}

/// Store key in macOS Keychain
fn storeKeyInKeychain(tag: []const u8, seed: *[32]u8, require_touch_id: bool) !void {
    // Convert tag to NSString
    const tag_ns = c.NSStringCreateWithUTF8(tag.ptr);
    if (tag_ns == null) return KeychainError.KeyStorageFailed;
    defer c.NSStringRelease(tag_ns);

    // Convert seed to NSData
    const seed_data = c.NSDataCreateWithBytes(seed.ptr, seed.len);
    if (seed_data == null) return KeychainError.KeyStorageFailed;
    defer c.NSDataRelease(seed_data);

    // Create query for Keychain
    var error_code: c_int = 0;
    const success = c.StoreKeyInKeychain(
        tag_ns,
        seed_data,
        require_touch_id,
        &error_code,
    );

    if (!success) {
        std.log.err("Keychain storage failed with error: {d}", .{error_code});
        return KeychainError.KeyStorageFailed;
    }
}

/// Load key from Keychain
pub fn loadKeyFromKeychain(
    allocator: Allocator,
    tag: []const u8,
) ![32]u8 {
    const tag_ns = c.NSStringCreateWithUTF8(tag.ptr);
    if (tag_ns == null) return KeychainError.KeyRetrievalFailed;
    defer c.NSStringRelease(tag_ns);

    var error_code: c_int = 0;
    const seed_data = c.LoadKeyFromKeychain(tag_ns, &error_code);

    if (seed_data == null) {
        std.log.err("Keychain retrieval failed with error: {d}", .{error_code});
        return KeychainError.KeyRetrievalFailed;
    }
    defer c.NSDataRelease(seed_data);

    const len = c.NSDataGetLength(seed_data);
    if (len != 32) return KeychainError.InvalidKeyFormat;

    const bytes = c.NSDataGetBytes(seed_data);
    var seed: [32]u8 = undefined;
    @memcpy(&seed, bytes[0..32]);

    return seed;
}

/// Delete key from Keychain
pub fn deleteKeyFromKeychain(tag: []const u8) !void {
    const tag_ns = c.NSStringCreateWithUTF8(tag.ptr);
    if (tag_ns == null) return KeychainError.KeyDeletionFailed;
    defer c.NSStringRelease(tag_ns);

    var error_code: c_int = 0;
    const success = c.DeleteKeyFromKeychain(tag_ns, &error_code);

    if (!success) {
        std.log.err("Keychain deletion failed with error: {d}", .{error_code});
        return KeychainError.KeyDeletionFailed;
    }
}

/// Check if Touch ID is available for Keychain protection
pub fn isTouchIDAvailable() bool {
    const context = c.LAContextCreate();
    if (context == null) return false;
    defer c.LAContextRelease(context);

    var error_code: c_int = 0;
    return c.LAContextCanEvaluatePolicy(
        context,
        2, // POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS
        &error_code,
    );
}

/// Prompt for Touch ID to unlock Keychain
pub fn promptTouchID(reason: []const u8) !bool {
    const context = c.LAContextCreate();
    if (context == null) return false;
    defer c.LAContextRelease(context);

    var error_code: c_int = 0;
    return c.LAContextEvaluatePolicySync(
        context,
        2, // POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS
        reason.ptr,
        &error_code,
    );
}

// Test functions
test "Software key generation" {
    const allocator = std.testing.allocator;

    const tag = "test-key-" ++ std.time.milliTimestamp();
    const keypair = try generateSoftwareKeyPair(allocator, tag, false);
    defer allocator.free(keypair.tag);

    try std.testing.expectEqual(keypair.public_key.len, 32);
    try std.testing.expectEqual(keypair.secret_key.len, 32);

    // Clean up
    deleteKeyFromKeychain(tag) catch {};
}
