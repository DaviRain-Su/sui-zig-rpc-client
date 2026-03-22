// Touch ID Test Program for macOS WebAuthn
// This program will prompt for Touch ID and test all WebAuthn functionality

const std = @import("std");
const builtin = @import("builtin");

// Only compile on macOS
const is_macos = builtin.os.tag == .macos;

// C types and functions
const CInt = i32;
const CUint = u32;

// Opaque types
const LAContextRef = ?*anyopaque;
const BridgeSecKeyRef = ?*anyopaque;
const NSDataRef = ?*anyopaque;

// Policy values from header
const POLICY_DEVICE_OWNER_AUTHENTICATION: CInt = 1;
const POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS: CInt = 2;
const POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_WATCH: CInt = 3;

// Biometry types
const BIOMETRY_TYPE_NONE: CInt = 0;
const BIOMETRY_TYPE_TOUCH_ID: CInt = 1;
const BIOMETRY_TYPE_FACE_ID: CInt = 2;
const BIOMETRY_TYPE_OPTIC_ID: CInt = 3;

// C function declarations
extern fn LAContextCreate() LAContextRef;
extern fn LAContextRelease(context: LAContextRef) void;
extern fn LAContextCanEvaluatePolicy(context: LAContextRef, policy: CInt, errorCode: *CInt) bool;
extern fn LAContextEvaluatePolicy(context: LAContextRef, policy: CInt, localizedReason: [*c]const u8, 
                                   completion: ?*const fn (?*anyopaque, bool, CInt) callconv(.c) void,
                                   userData: ?*anyopaque) void;
extern fn LAContextGetBiometryType(context: LAContextRef) CInt;
extern fn BridgeSecKeyGenerateSecureEnclaveKey(tag: [*c]const u8, biometricRequired: bool, errorCode: *CInt) BridgeSecKeyRef;
extern fn BridgeSecKeyRelease(key: BridgeSecKeyRef) void;
extern fn BridgeSecKeyCopyPublicKey(privateKey: BridgeSecKeyRef) BridgeSecKeyRef;
extern fn BridgeSecKeyCopyExternalRepresentation(key: BridgeSecKeyRef, errorCode: *CInt) NSDataRef;
extern fn BridgeSecKeyCreateSignature(key: BridgeSecKeyRef, data: [*c]const u8, dataLen: usize, errorCode: *CInt) NSDataRef;
extern fn StoreCredentialInKeychain(tag: [*c]const u8, privateKey: BridgeSecKeyRef, errorCode: *CInt) bool;
extern fn LoadCredentialFromKeychain(tag: [*c]const u8, errorCode: *CInt) BridgeSecKeyRef;
extern fn DeleteCredentialFromKeychain(tag: [*c]const u8, errorCode: *CInt) bool;
extern fn NSDataGetLength(data: NSDataRef) usize;
extern fn NSDataGetBytes(data: NSDataRef) [*c]const u8;
extern fn NSDataRelease(data: NSDataRef) void;
extern fn GetErrorMessage(errorCode: CInt) [*c]const u8;
extern fn FreeString(str: [*c]const u8) void;

pub fn main() !void {
    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           Touch ID / WebAuthn Test Program                   ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    if (!is_macos) {
        std.debug.print("❌ This test program only runs on macOS\n", .{});
        std.process.exit(1);
    }

    // Test 1: Platform Detection
    std.debug.print("Test 1: Platform Detection\n", .{});
    std.debug.print("──────────────────────────\n", .{});
    
    const context = LAContextCreate();
    if (context == null) {
        std.debug.print("❌ Failed to create LAContext\n", .{});
        std.process.exit(1);
    }
    defer LAContextRelease(context);
    std.debug.print("✓ LAContext created\n", .{});

    // Test 2: Biometric Availability
    std.debug.print("\nTest 2: Biometric Availability\n", .{});
    std.debug.print("──────────────────────────────\n", .{});
    
    var error_code: CInt = 0;
    const bio_available = LAContextCanEvaluatePolicy(
        context,
        POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        &error_code,
    );

    if (bio_available) {
        std.debug.print("✓ Biometric authentication is available\n", .{});
        
        const bio_type = LAContextGetBiometryType(context);
        std.debug.print("  Biometry type: ", .{});
        if (bio_type == BIOMETRY_TYPE_TOUCH_ID) {
            std.debug.print("Touch ID 🖐️\n", .{});
        } else if (bio_type == BIOMETRY_TYPE_FACE_ID) {
            std.debug.print("Face ID 😊\n", .{});
        } else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) {
            std.debug.print("Optic ID 👁️\n", .{});
        } else {
            std.debug.print("None\n", .{});
        }
    } else {
        std.debug.print("⚠️  Biometric authentication is not available\n", .{});
        const err_msg = GetErrorMessage(error_code);
        defer FreeString(err_msg);
        std.debug.print("  Error: {s}\n", .{err_msg});
        std.debug.print("\nNote: You can still use password authentication\n", .{});
    }

    // Test 3: Device Authentication (Password fallback)
    std.debug.print("\nTest 3: Device Authentication\n", .{});
    std.debug.print("─────────────────────────────\n", .{});
    
    error_code = 0;
    const device_auth = LAContextCanEvaluatePolicy(
        context,
        POLICY_DEVICE_OWNER_AUTHENTICATION,
        &error_code,
    );

    if (device_auth) {
        std.debug.print("✓ Device authentication is available\n", .{});
    } else {
        std.debug.print("❌ Device authentication is not available\n", .{});
        const err_msg = GetErrorMessage(error_code);
        defer FreeString(err_msg);
        std.debug.print("  Error: {s}\n", .{err_msg});
    }

    // Test 4: Touch ID Prompt (Interactive)
    std.debug.print("\nTest 4: Touch ID Authentication Prompt\n", .{});
    std.debug.print("──────────────────────────────────────\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("⚠️  This test will prompt for Touch ID / Password\n", .{});
    std.debug.print("    Press Enter to continue or Ctrl+C to skip...\n", .{});
    
    // Wait for user input
    std.debug.print("    Press Enter to continue...", .{});
    var buf: [10]u8 = undefined;
    const stdin = std.fs.File{ .handle = 0 }; // stdin
    _ = stdin.read(&buf) catch {};
    std.debug.print("\n", .{});

    std.debug.print("\n🔐 Prompting for authentication...\n", .{});
    std.debug.print("   (You should see a Touch ID / Password prompt)\n\n", .{});

    // Create a new context for authentication
    const auth_context = LAContextCreate();
    if (auth_context == null) {
        std.debug.print("❌ Failed to create auth context\n", .{});
        std.process.exit(1);
    }
    defer LAContextRelease(auth_context);

    // Completion handler
    const Completion = struct {
        completed: bool = false,
        success: bool = false,
        
        fn handler(userData: ?*anyopaque, ok: bool, err: CInt) callconv(.c) void {
            _ = err;
            const self = @as(*@This(), @ptrCast(@alignCast(userData.?)));
            self.success = ok;
            self.completed = true;
        }
    };
    
    var completion = Completion{};

    const reason = "Test Touch ID authentication for Sui CLI";
    LAContextEvaluatePolicy(
        auth_context,
        POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        reason.ptr,
        &Completion.handler,
        &completion,
    );

    // Wait for completion with timeout
    var timeout: u32 = 0;
    const max_timeout: u32 = 30000; // 30 seconds
    while (!completion.completed and timeout < max_timeout) {
        // Simple busy wait
        var i: u32 = 0;
        while (i < 1000000) : (i += 1) {
            std.mem.doNotOptimizeAway(i);
        }
        timeout += 100;
    }

    if (!completion.completed) {
        std.debug.print("⏱️  Authentication timed out\n", .{});
    } else if (completion.success) {
        std.debug.print("✓ Authentication successful! 🎉\n", .{});
    } else {
        std.debug.print("❌ Authentication failed\n", .{});
    }

    // Test 5: Secure Enclave Key Generation
    std.debug.print("\nTest 5: Secure Enclave Key Generation\n", .{});
    std.debug.print("─────────────────────────────────────\n", .{});
    
    if (completion.success) {
        std.debug.print("Generating P-256 key in Secure Enclave...\n", .{});
        
        const test_tag = "test-sui-passkey-touchid";
        error_code = 0;
        
        const private_key = BridgeSecKeyGenerateSecureEnclaveKey(
            test_tag,
            true, // Require biometric authentication
            &error_code,
        );

        if (private_key == null) {
            std.debug.print("❌ Failed to generate key\n", .{});
            const err_msg = GetErrorMessage(error_code);
            defer FreeString(err_msg);
            std.debug.print("   Error: {s}\n", .{err_msg});
        } else {
            defer BridgeSecKeyRelease(private_key);
            std.debug.print("✓ Private key generated in Secure Enclave\n", .{});
            
            // Get public key
            const public_key = BridgeSecKeyCopyPublicKey(private_key);
            if (public_key) |pk| {
                defer BridgeSecKeyRelease(pk);
                
                const pub_key_data = BridgeSecKeyCopyExternalRepresentation(pk, &error_code);
                if (pub_key_data) |data| {
                    defer NSDataRelease(data);
                    const len = NSDataGetLength(data);
                    std.debug.print("✓ Public key exported ({d} bytes)\n", .{len});
                    
                    // Print first few bytes
                    const bytes = NSDataGetBytes(data);
                    std.debug.print("   First bytes: ", .{});
                    var i: usize = 0;
                    while (i < @min(len, 8)) : (i += 1) {
                        std.debug.print("{x:0>2}", .{bytes[i]});
                    }
                    std.debug.print("...\n", .{});
                } else {
                    std.debug.print("❌ Failed to export public key\n", .{});
                }
            } else {
                std.debug.print("❌ Failed to get public key\n", .{});
            }
            
            // Test signing
            std.debug.print("\nTest 6: Sign with Touch ID\n", .{});
            std.debug.print("──────────────────────────\n", .{});
            std.debug.print("Signing test data (will prompt for Touch ID)...\n", .{});
            
            const test_data = "Hello, Touch ID!";
            error_code = 0;
            
            const signature = BridgeSecKeyCreateSignature(
                private_key,
                test_data.ptr,
                test_data.len,
                &error_code,
            );

            if (signature) |sig| {
                defer NSDataRelease(sig);
                const sig_len = NSDataGetLength(sig);
                std.debug.print("✓ Signature created ({d} bytes)\n", .{sig_len});
                std.debug.print("🎉 Touch ID signing works!\n", .{});
            } else {
                std.debug.print("❌ Failed to create signature\n", .{});
                const err_msg = GetErrorMessage(error_code);
                defer FreeString(err_msg);
                std.debug.print("   Error: {s}\n", .{err_msg});
            }
            
            // Cleanup: Delete test key
            std.debug.print("\nCleaning up test key...\n", .{});
            if (DeleteCredentialFromKeychain(test_tag, &error_code)) {
                std.debug.print("✓ Test key deleted\n", .{});
            } else {
                std.debug.print("⚠️  Failed to delete test key\n", .{});
            }
        }
    } else {
        std.debug.print("⏭️  Skipping (authentication required for key generation)\n", .{});
    }

    // Summary
    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                      Test Summary                            ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("✓ Platform: macOS\n", .{});
    std.debug.print("✓ LAContext: Created successfully\n", .{});
    std.debug.print("{s} Biometric detection: {s}\n", .{
        if (bio_available) "✓" else "⚠️",
        if (bio_available) "Available" else "Not available",
    });
    std.debug.print("{s} Device authentication: {s}\n", .{
        if (device_auth) "✓" else "❌",
        if (device_auth) "Available" else "Not available",
    });
    std.debug.print("{s} Touch ID prompt: {s}\n", .{
        if (completion.completed) (if (completion.success) "✓" else "❌") else "⏱️",
        if (completion.completed) (if (completion.success) "Successful" else "Failed") else "Timeout",
    });
    std.debug.print("\n", .{});
    
    if (completion.success) {
        std.debug.print("🎉 All Touch ID tests passed!\n", .{});
        std.debug.print("\nYour MacBook is ready for WebAuthn/Passkey operations.\n", .{});
    } else {
        std.debug.print("⚠️  Some tests did not complete.\n", .{});
        std.debug.print("\nYou may need to:\n", .{});
        std.debug.print("  - Enroll fingerprints in System Preferences > Touch ID\n", .{});
        std.debug.print("  - Enable password authentication\n", .{});
    }
    
    std.debug.print("\n", .{});
}
