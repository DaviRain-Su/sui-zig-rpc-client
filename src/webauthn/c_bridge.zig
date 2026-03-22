// C bridge for WebAuthn on macOS
// Imports the Objective-C bridge functions

const std = @import("std");

// Only compile on macOS
const builtin = @import("builtin");
const is_macos = builtin.os.tag == .macos;

// C types
pub const c = if (is_macos) @cImport({
    @cInclude("macos_bridge.h");
}) else struct {};

// Re-export types for easier access
pub const LAContextRef = if (is_macos) c.LAContextRef else *anyopaque;
pub const BridgeSecKeyRef = if (is_macos) c.BridgeSecKeyRef else *anyopaque;
pub const NSDataRef = if (is_macos) c.NSDataRef else *anyopaque;
pub const NSStringRef = if (is_macos) c.NSStringRef else *anyopaque;

// Policy enum
pub const BridgeLAPolicy = if (is_macos) c.BridgeLAPolicy else enum(c_int) {
    device_owner_authentication = 1,
    device_owner_authentication_with_biometrics = 2,
    device_owner_authentication_with_watch = 3,
};

// Error enum
pub const BridgeLAError = if (is_macos) c.BridgeLAError else enum(c_int) {
    success = 0,
    authentication_failed = -1,
    user_cancel = -2,
    user_fallback = -3,
    biometry_not_available = -4,
    biometry_not_enrolled = -5,
    biometry_lockout = -6,
    invalid_context = -7,
    not_interactive = -8,
    watch_not_available = -9,
    biometry_not_preferred = -10,
    credential_set_expired = -11,
    passcode_not_set = -12,
    system_cancel = -13,
    invalid_dimensions = -14,
    other = -99,
};

// Biometry type enum
pub const BridgeBiometryType = if (is_macos) c.BridgeBiometryType else enum(c_int) {
    none = 0,
    touch_id = 1,
    face_id = 2,
    optic_id = 3,
};

// LAContext functions
pub extern fn LAContextCreate() LAContextRef;
pub extern fn LAContextRelease(context: LAContextRef) void;
pub extern fn LAContextCanEvaluatePolicy(context: LAContextRef, policy: BridgeLAPolicy, errorCode: *c_int) bool;
pub extern fn LAContextEvaluatePolicy(context: LAContextRef, policy: BridgeLAPolicy, localizedReason: [*c]const u8, completion: *const fn (success: bool, errorCode: c_int) callconv(.C) void) void;
pub extern fn LAContextEvaluatePolicySync(context: LAContextRef, policy: BridgeLAPolicy, localizedReason: [*c]const u8, errorCode: *c_int) bool;
pub extern fn LAContextGetBiometryType(context: LAContextRef) BridgeBiometryType;

// Secure Enclave functions
pub extern fn BridgeSecKeyGenerateSecureEnclaveKey(tag: [*c]const u8, biometricRequired: bool, errorCode: *c_int) BridgeSecKeyRef;
pub extern fn BridgeSecKeyRelease(key: BridgeSecKeyRef) void;
pub extern fn BridgeSecKeyCopyPublicKey(privateKey: BridgeSecKeyRef) BridgeSecKeyRef;
pub extern fn BridgeSecKeyCopyExternalRepresentation(key: BridgeSecKeyRef, errorCode: *c_int) NSDataRef;
pub extern fn BridgeSecKeyCreateSignature(key: BridgeSecKeyRef, data: [*c]const u8, dataLen: usize, errorCode: *c_int) NSDataRef;

// Keychain functions
pub extern fn StoreCredentialInKeychain(tag: [*c]const u8, privateKey: BridgeSecKeyRef, errorCode: *c_int) bool;
pub extern fn LoadCredentialFromKeychain(tag: [*c]const u8, errorCode: *c_int) BridgeSecKeyRef;
pub extern fn DeleteCredentialFromKeychain(tag: [*c]const u8, errorCode: *c_int) bool;

// NSString helpers
pub extern fn NSStringCreateWithUTF8(str: [*c]const u8) NSStringRef;
pub extern fn NSStringGetUTF8(str: NSStringRef) [*c]const u8;
pub extern fn NSStringRelease(str: NSStringRef) void;

// NSData helpers
pub extern fn NSDataGetLength(data: NSDataRef) usize;
pub extern fn NSDataGetBytes(data: NSDataRef) [*c]const u8;
pub extern fn NSDataRelease(data: NSDataRef) void;

// Utility
pub extern fn GetErrorMessage(errorCode: c_int) [*c]const u8;
pub extern fn FreeString(str: [*c]const u8) void;

// Helper function to convert NSData to Zig slice
pub fn nsDataToSlice(data: NSDataRef) []const u8 {
    if (data == null) return &[_]u8{};
    const len = NSDataGetLength(data);
    const bytes = NSDataGetBytes(data);
    return bytes[0..len];
}

// Helper function to get error message as Zig string
pub fn getErrorMessageZig(errorCode: c_int, allocator: std.mem.Allocator) ![]const u8 {
    const c_msg = GetErrorMessage(errorCode);
    defer FreeString(c_msg);
    return try allocator.dupe(u8, std.mem.span(c_msg));
}
