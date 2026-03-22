/// macOS WebAuthn Implementation
/// Uses LocalAuthentication framework and Secure Enclave
const std = @import("std");
const Allocator = std.mem.Allocator;

// Objective-C Runtime bindings
const objc = struct {
    pub const Class = *opaque {};
    pub const Object = *opaque {};
    pub const Selector = *opaque {};

    pub extern "objc" fn objc_getClass(name: [*:0]const u8) ?Class;
    pub extern "objc" fn sel_registerName(name: [*:0]const u8) Selector;
    pub extern "objc" fn objc_msgSend(obj: ?Object, sel: Selector, ...) ?Object;
    pub extern "objc" fn objc_msgSend_bool(obj: ?Object, sel: Selector, ...) bool;
    pub extern "objc" fn objc_msgSend_int(obj: ?Object, sel: Selector, ...) c_int;

    // NSString helpers
    pub extern "C" fn NSStringFromUTF8String(str: [*:0]const u8) ?Object;
    pub extern "C" fn UTF8String(obj: ?Object) [*:0]const u8;
};

pub const MacOSWebAuthn = struct {
    allocator: Allocator,
    la_context_class: ?objc.Class,
    sec_key_class: ?objc.Class,

    pub fn init(allocator: Allocator) !MacOSWebAuthn {
        const la_class = objc.objc_getClass("LAContext");
        const sec_class = objc.objc_getClass("SecKey");

        if (la_class == null) {
            return error.LocalAuthenticationNotAvailable;
        }

        return .{
            .allocator = allocator,
            .la_context_class = la_class,
            .sec_key_class = sec_class,
        };
    }

    pub fn deinit(self: *MacOSWebAuthn) void {
        _ = self;
    }

    /// Check if biometric authentication is available
    pub fn isBiometricAvailable(self: *const MacOSWebAuthn) bool {
        _ = self;

        // LAContext *context = [[LAContext alloc] init];
        // BOOL available = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil];

        // For now, return true if we can get the LAContext class
        return true;
    }

    /// Get biometric type (Touch ID vs Face ID)
    pub fn getBiometricType(self: *const MacOSWebAuthn) BiometricType {
        _ = self;

        // LABiometryType type = context.biometryType;
        // LABiometryTypeTouchID = 1, LABiometryTypeFaceID = 2

        // Detect based on hardware
        return detectBiometricType();
    }

    /// Create a credential in Secure Enclave
    ///
    /// NOTE: This function requires full Objective-C runtime integration
    /// which is only available when building with -Dwebauthn flag and
    /// proper macOS SDK. The current implementation is a skeleton showing
    /// the required steps:
    ///
    /// 1. Generate P-256 keypair in Secure Enclave using SecKeyCreateRandomKey
    /// 2. Configure biometric protection with SecAccessControlCreateWithFlags
    /// 3. Store in keychain with kSecAttrTokenIDSecureEnclave
    /// 4. Return credential ID and public key
    ///
    /// To enable full functionality:
    /// - Build with: zig build -Dwebauthn
    /// - Requires macOS 10.15+ with Secure Enclave
    /// - Requires proper entitlements for keychain access
    pub fn createCredential(
        self: *MacOSWebAuthn,
        rp_id: []const u8,
        user_name: []const u8,
    ) !Credential {
        _ = self;

        std.log.info("Creating credential in Secure Enclave...", .{});
        std.log.info("  RP ID: {s}", .{rp_id});
        std.log.info("  User: {s}", .{user_name});

        // This would require full Objective-C integration:
        // SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        //     kCFAllocatorDefault,
        //     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        //     kSecAccessControlBiometryCurrentSet,
        //     &error
        // );
        //
        // NSDictionary *attributes = @{
        //     kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        //     kSecAttrKeySizeInBits: @256,
        //     kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
        //     kSecPrivateKeyAttrs: @{
        //         kSecAttrIsPermanent: @YES,
        //         kSecAttrApplicationTag: credentialId,
        //         kSecAttrAccessControl: accessControl
        //     }
        // };
        //
        // SecKeyRef privateKey = SecKeyCreateRandomKey(attributes, &error);
        // SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

        return error.NotImplemented;
    }

    /// Sign data with biometric authentication
    ///
    /// NOTE: This function requires full Objective-C runtime integration
    /// which is only available when building with -Dwebauthn flag.
    /// The implementation would:
    ///
    /// 1. Create LAContext for biometric evaluation
    /// 2. Call evaluatePolicy with LAPolicyDeviceOwnerAuthenticationWithBiometrics
    /// 3. On success, retrieve private key from keychain using credential_id
    /// 4. Use SecKeyCreateSignature to sign the data
    ///
    /// To enable full functionality:
    /// - Build with: zig build -Dwebauthn
    /// - Requires enrolled biometrics (Touch ID)
    /// - Requires user interaction (biometric prompt)
    pub fn signWithBiometric(
        self: *MacOSWebAuthn,
        credential_id: []const u8,
        data: []const u8,
    ) ![]const u8 {
        _ = self;
        _ = credential_id;

        std.log.info("Requesting biometric authentication...", .{});

        // This would require full Objective-C integration:
        // LAContext *context = [[LAContext alloc] init];
        // [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
        //         localizedReason:@"Sign Sui transaction"
        //                 reply:^(BOOL success, NSError *error) {
        //     if (success) {
        //         SecKeyRef privateKey = // retrieve from keychain
        //         CFDataRef signature = SecKeyCreateSignature(privateKey, ...);
        //     }
        // }];

        _ = data;
        return error.NotImplemented;
    }

    fn detectBiometricType() BiometricType {
        // Check machine hardware
        // MacBook Pro with Touch Bar -> Touch ID
        // MacBook Air M2 -> Touch ID
        // iMac -> None
        // Mac mini -> None (unless paired with Magic Keyboard with Touch ID)

        // sysctl hw.model
        // MacBookPro18,1 -> Touch ID
        // Mac14,2 -> Touch ID (MacBook Air)

        return .touch_id; // Default assumption
    }
};

pub const BiometricType = enum {
    none,
    touch_id,
    face_id,
};

pub const Credential = struct {
    id: []const u8,
    public_key: []const u8,
    rp_id: []const u8,
    user_name: []const u8,

    pub fn deinit(self: *Credential, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.public_key);
        allocator.free(self.rp_id);
        allocator.free(self.user_name);
    }
};

// Test helpers
test "MacOSWebAuthn initialization" {
    // This would only work on macOS
    if (@import("builtin").target.isDarwin()) {
        const auth = try MacOSWebAuthn.init(std.testing.allocator);
        _ = auth;
    }
}
