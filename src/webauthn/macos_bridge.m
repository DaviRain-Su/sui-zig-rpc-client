// macOS WebAuthn Bridge Implementation
// Objective-C implementation for LocalAuthentication and Secure Enclave

#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import "macos_bridge.h"

// MARK: - Type Mappings

// Map our bridge types to system types
static LAPolicy MapPolicy(BridgeLAPolicy policy) {
    switch (policy) {
        case BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION:
            return LAPolicyDeviceOwnerAuthentication;
        case BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS:
            return LAPolicyDeviceOwnerAuthenticationWithBiometrics;
        case BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_WATCH:
            return LAPolicyDeviceOwnerAuthenticationWithWatch;
        default:
            return LAPolicyDeviceOwnerAuthentication;
    }
}

static BridgeBiometryType MapBiometryType(LABiometryType type) {
    switch (type) {
        case LABiometryTypeTouchID:
            return BRIDGE_BIOMETRY_TYPE_TOUCH_ID;
        case LABiometryTypeFaceID:
            return BRIDGE_BIOMETRY_TYPE_FACE_ID;
        case LABiometryTypeOpticID:
            return BRIDGE_BIOMETRY_TYPE_OPTIC_ID;
        default:
            return BRIDGE_BIOMETRY_TYPE_NONE;
    }
}

static int32_t MapErrorCode(NSError *error) {
    if (!error) return BRIDGE_LA_ERROR_SUCCESS;
    
    switch (error.code) {
        case LAErrorAuthenticationFailed:
            return BRIDGE_LA_ERROR_AUTHENTICATION_FAILED;
        case LAErrorUserCancel:
            return BRIDGE_LA_ERROR_USER_CANCEL;
        case LAErrorUserFallback:
            return BRIDGE_LA_ERROR_USER_FALLBACK;
        case LAErrorBiometryNotAvailable:
            return BRIDGE_LA_ERROR_BIOMETRY_NOT_AVAILABLE;
        case LAErrorBiometryNotEnrolled:
            return BRIDGE_LA_ERROR_BIOMETRY_NOT_ENROLLED;
        case LAErrorBiometryLockout:
            return BRIDGE_LA_ERROR_BIOMETRY_LOCKOUT;
        case LAErrorInvalidContext:
            return BRIDGE_LA_ERROR_INVALID_CONTEXT;
        case LAErrorNotInteractive:
            return BRIDGE_LA_ERROR_NOT_INTERACTIVE;
        case LAErrorWatchNotAvailable:
            return BRIDGE_LA_ERROR_WATCH_NOT_AVAILABLE;
        case LAErrorBiometryNotPaired:
            return BRIDGE_LA_ERROR_BIOMETRY_NOT_PREFERRED;
        case LAErrorPasscodeNotSet:
            return BRIDGE_LA_ERROR_PASSCODE_NOT_SET;
        case LAErrorSystemCancel:
            return BRIDGE_LA_ERROR_SYSTEM_CANCEL;
        default:
            return BRIDGE_LA_ERROR_OTHER;
    }
}

// MARK: - LAContext Implementation

LAContextRef LAContextCreate(void) {
    LAContext *context = [[LAContext alloc] init];
    return (LAContextRef)CFBridgingRetain(context);
}

void LAContextRelease(LAContextRef context) {
    if (context) {
        CFRelease(context);
    }
}

bool LAContextCanEvaluatePolicy(LAContextRef context, BridgeLAPolicy policy, int32_t* errorCode) {
    if (!context) return false;
    
    LAContext *ctx = (__bridge LAContext *)context;
    NSError *error = nil;
    
    BOOL canEvaluate = [ctx canEvaluatePolicy:MapPolicy(policy) error:&error];
    
    if (errorCode) {
        *errorCode = MapErrorCode(error);
    }
    
    return canEvaluate ? true : false;
}

void LAContextEvaluatePolicy(LAContextRef context, BridgeLAPolicy policy, const char* localizedReason, 
                              void (*completion)(bool success, int32_t errorCode)) {
    if (!context || !localizedReason || !completion) {
        if (completion) completion(false, BRIDGE_LA_ERROR_INVALID_CONTEXT);
        return;
    }
    
    LAContext *ctx = (__bridge LAContext *)context;
    NSString *reason = [NSString stringWithUTF8String:localizedReason];
    
    [ctx evaluatePolicy:MapPolicy(policy) localizedReason:reason reply:^(BOOL success, NSError *error) {
        completion(success ? true : false, MapErrorCode(error));
    }];
}

BridgeBiometryType LAContextGetBiometryType(LAContextRef context) {
    if (!context) return BRIDGE_BIOMETRY_TYPE_NONE;
    
    LAContext *ctx = (__bridge LAContext *)context;
    return MapBiometryType(ctx.biometryType);
}

// Synchronous authentication with run loop for UI
bool LAContextEvaluatePolicySync(LAContextRef context, BridgeLAPolicy policy, const char* localizedReason, int32_t* errorCode) {
    if (!context || !localizedReason) {
        if (errorCode) *errorCode = BRIDGE_LA_ERROR_INVALID_CONTEXT;
        return false;
    }
    
    LAContext *ctx = (__bridge LAContext *)context;
    NSString *reason = [NSString stringWithUTF8String:localizedReason];
    
    __block BOOL success = NO;
    __block int32_t errCode = BRIDGE_LA_ERROR_SUCCESS;
    __block BOOL completed = NO;
    
    // Evaluate policy
    [ctx evaluatePolicy:MapPolicy(policy) localizedReason:reason reply:^(BOOL ok, NSError *error) {
        success = ok;
        errCode = MapErrorCode(error);
        completed = YES;
    }];
    
    // Run the run loop until completion
    while (!completed) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    
    if (errorCode) *errorCode = errCode;
    return success ? true : false;
}

// MARK: - Secure Enclave Key Generation

BridgeSecKeyRef BridgeSecKeyGenerateSecureEnclaveKey(const char* tag, bool biometricRequired, int32_t* errorCode) {
    if (!tag) {
        if (errorCode) *errorCode = BRIDGE_LA_ERROR_INVALID_CONTEXT;
        return NULL;
    }
    
    NSString *tagString = [NSString stringWithUTF8String:tag];
    NSData *tagData = [tagString dataUsingEncoding:NSUTF8StringEncoding];
    
    // Create access control
    SecAccessControlCreateFlags flags = kSecAccessControlPrivateKeyUsage;
    if (biometricRequired) {
        flags |= kSecAccessControlBiometryCurrentSet;
    }
    
    CFErrorRef error = NULL;
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        flags,
        &error
    );
    
    if (error) {
        if (errorCode) *errorCode = (int32_t)CFErrorGetCode(error);
        CFRelease(error);
        return NULL;
    }
    
    // Key attributes
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @YES,
            (__bridge id)kSecAttrApplicationTag: tagData,
            (__bridge id)kSecAttrAccessControl: (__bridge_transfer id)accessControl
        }
    };
    
    CFErrorRef keyError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &keyError);
    
    if (keyError) {
        if (errorCode) *errorCode = (int32_t)CFErrorGetCode(keyError);
        CFRelease(keyError);
        return NULL;
    }
    
    if (errorCode) *errorCode = BRIDGE_LA_ERROR_SUCCESS;
    return (BridgeSecKeyRef)privateKey;
}

void BridgeSecKeyRelease(BridgeSecKeyRef key) {
    if (key) {
        CFRelease((SecKeyRef)key);
    }
}

BridgeSecKeyRef BridgeSecKeyCopyPublicKey(BridgeSecKeyRef privateKey) {
    if (!privateKey) return NULL;
    
    SecKeyRef publicKey = SecKeyCopyPublicKey((SecKeyRef)privateKey);
    
    if (publicKey) {
        return (BridgeSecKeyRef)publicKey;
    }
    return NULL;
}

NSDataRef BridgeSecKeyCopyExternalRepresentation(BridgeSecKeyRef key, int32_t* errorCode) {
    if (!key) {
        if (errorCode) *errorCode = BRIDGE_LA_ERROR_INVALID_CONTEXT;
        return NULL;
    }
    
    CFErrorRef error = NULL;
    CFDataRef data = SecKeyCopyExternalRepresentation((SecKeyRef)key, &error);
    
    if (error) {
        if (errorCode) *errorCode = (int32_t)CFErrorGetCode(error);
        CFRelease(error);
        return NULL;
    }
    
    if (errorCode) *errorCode = BRIDGE_LA_ERROR_SUCCESS;
    return (NSDataRef)data;
}

// MARK: - Signing

NSDataRef BridgeSecKeyCreateSignature(BridgeSecKeyRef key, const uint8_t* data, size_t dataLen, int32_t* errorCode) {
    if (!key || !data || dataLen == 0) {
        if (errorCode) *errorCode = BRIDGE_LA_ERROR_INVALID_CONTEXT;
        return NULL;
    }
    
    NSData *dataToSign = [NSData dataWithBytes:data length:dataLen];
    
    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(
        (SecKeyRef)key,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)dataToSign,
        &error
    );
    
    if (error) {
        if (errorCode) *errorCode = (int32_t)CFErrorGetCode(error);
        CFRelease(error);
        return NULL;
    }
    
    if (errorCode) *errorCode = BRIDGE_LA_ERROR_SUCCESS;
    return (NSDataRef)signature;
}

// MARK: - NSString Helpers

NSStringRef NSStringCreateWithUTF8(const char* str) {
    if (!str) return NULL;
    NSString *nsstr = [NSString stringWithUTF8String:str];
    return (NSStringRef)CFBridgingRetain(nsstr);
}

const char* NSStringGetUTF8(NSStringRef str) {
    if (!str) return NULL;
    NSString *nsstr = (__bridge NSString *)str;
    return [nsstr UTF8String];
}

void NSStringRelease(NSStringRef str) {
    if (str) {
        CFRelease(str);
    }
}

// MARK: - NSData Helpers

size_t NSDataGetLength(NSDataRef data) {
    if (!data) return 0;
    NSData *d = (__bridge NSData *)data;
    return d.length;
}

const uint8_t* NSDataGetBytes(NSDataRef data) {
    if (!data) return NULL;
    NSData *d = (__bridge NSData *)data;
    return (const uint8_t*)d.bytes;
}

void NSDataRelease(NSDataRef data) {
    if (data) {
        CFRelease(data);
    }
}

// MARK: - Keychain Storage

bool StoreCredentialInKeychain(const char* tag, BridgeSecKeyRef privateKey, int32_t* errorCode) {
    // Key is already stored in keychain via kSecAttrIsPermanent during generation
    (void)tag;
    (void)privateKey;
    if (errorCode) *errorCode = BRIDGE_LA_ERROR_SUCCESS;
    return true;
}

BridgeSecKeyRef LoadCredentialFromKeychain(const char* tag, int32_t* errorCode) {
    if (!tag) {
        if (errorCode) *errorCode = BRIDGE_LA_ERROR_INVALID_CONTEXT;
        return NULL;
    }
    
    NSString *tagString = [NSString stringWithUTF8String:tag];
    NSData *tagData = [tagString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: tagData,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecReturnRef: @YES
    };
    
    SecKeyRef key = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&key);
    
    if (status != errSecSuccess) {
        if (errorCode) *errorCode = (int32_t)status;
        return NULL;
    }
    
    if (errorCode) *errorCode = BRIDGE_LA_ERROR_SUCCESS;
    return (BridgeSecKeyRef)key;
}

bool DeleteCredentialFromKeychain(const char* tag, int32_t* errorCode) {
    if (!tag) {
        if (errorCode) *errorCode = BRIDGE_LA_ERROR_INVALID_CONTEXT;
        return false;
    }
    
    NSString *tagString = [NSString stringWithUTF8String:tag];
    NSData *tagData = [tagString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: tagData,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom
    };
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (errorCode) *errorCode = (int32_t)status;
        return false;
    }
    
    if (errorCode) *errorCode = BRIDGE_LA_ERROR_SUCCESS;
    return true;
}

// MARK: - Utility

const char* GetErrorMessage(int32_t errorCode) {
    NSString *message = nil;
    
    switch (errorCode) {
        case BRIDGE_LA_ERROR_SUCCESS:
            message = @"Success";
            break;
        case BRIDGE_LA_ERROR_AUTHENTICATION_FAILED:
            message = @"Authentication failed";
            break;
        case BRIDGE_LA_ERROR_USER_CANCEL:
            message = @"User cancelled";
            break;
        case BRIDGE_LA_ERROR_USER_FALLBACK:
            message = @"User chose to use fallback";
            break;
        case BRIDGE_LA_ERROR_BIOMETRY_NOT_AVAILABLE:
            message = @"Biometry is not available on this device";
            break;
        case BRIDGE_LA_ERROR_BIOMETRY_NOT_ENROLLED:
            message = @"No biometric credentials are enrolled";
            break;
        case BRIDGE_LA_ERROR_BIOMETRY_LOCKOUT:
            message = @"Biometry is locked out";
            break;
        case BRIDGE_LA_ERROR_INVALID_CONTEXT:
            message = @"Invalid context";
            break;
        case BRIDGE_LA_ERROR_NOT_INTERACTIVE:
            message = @"Not interactive";
            break;
        case BRIDGE_LA_ERROR_WATCH_NOT_AVAILABLE:
            message = @"Apple Watch is not available";
            break;
        case BRIDGE_LA_ERROR_PASSCODE_NOT_SET:
            message = @"Passcode is not set";
            break;
        default:
            message = [NSString stringWithFormat:@"Unknown error: %d", errorCode];
            break;
    }
    
    return strdup([message UTF8String]);
}

void FreeString(const char* str) {
    if (str) {
        free((void*)str);
    }
}
