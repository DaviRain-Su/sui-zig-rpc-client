// macOS WebAuthn Bridge Implementation
// Objective-C implementation for LocalAuthentication and Secure Enclave

#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import "macos_bridge.h"

// MARK: - LAContext Implementation

LAContextRef LAContextCreate(void) {
    LAContext *context = [[LAContext alloc] init];
    return (__bridge_retained LAContextRef)context;
}

void LAContextRelease(LAContextRef context) {
    if (context) {
        LAContext *ctx = (__bridge_transfer LAContext *)context;
        (void)ctx; // ARC handles release
    }
}

bool LAContextCanEvaluatePolicy(LAContextRef context, LAPolicy policy, int32_t* errorCode) {
    if (!context) return false;
    
    LAContext *ctx = (__bridge LAContext *)context;
    NSError *error = nil;
    
    LAPolicy laPolicy;
    switch (policy) {
        case POLICY_DEVICE_OWNER_AUTHENTICATION:
            laPolicy = LAPolicyDeviceOwnerAuthentication;
            break;
        case POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS:
            laPolicy = LAPolicyDeviceOwnerAuthenticationWithBiometrics;
            break;
        case POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_WATCH:
            laPolicy = LAPolicyDeviceOwnerAuthenticationWithWatch;
            break;
        default:
            if (errorCode) *errorCode = LA_ERROR_INVALID_CONTEXT;
            return false;
    }
    
    BOOL canEvaluate = [ctx canEvaluatePolicy:laPolicy error:&error];
    
    if (error && errorCode) {
        *errorCode = (int32_t)error.code;
    } else if (!canEvaluate && errorCode) {
        *errorCode = LA_ERROR_BIOMETRY_NOT_AVAILABLE;
    } else if (errorCode) {
        *errorCode = LA_ERROR_SUCCESS;
    }
    
    return canEvaluate ? true : false;
}

void LAContextEvaluatePolicy(LAContextRef context, LAPolicy policy, const char* localizedReason, 
                              void (*completion)(bool success, int32_t errorCode)) {
    if (!context || !localizedReason || !completion) {
        if (completion) completion(false, LA_ERROR_INVALID_CONTEXT);
        return;
    }
    
    LAContext *ctx = (__bridge LAContext *)context;
    NSString *reason = [NSString stringWithUTF8String:localizedReason];
    
    LAPolicy laPolicy;
    switch (policy) {
        case POLICY_DEVICE_OWNER_AUTHENTICATION:
            laPolicy = LAPolicyDeviceOwnerAuthentication;
            break;
        case POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS:
            laPolicy = LAPolicyDeviceOwnerAuthenticationWithBiometrics;
            break;
        case POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_WATCH:
            laPolicy = LAPolicyDeviceOwnerAuthenticationWithWatch;
            break;
        default:
            completion(false, LA_ERROR_INVALID_CONTEXT);
            return;
    }
    
    [ctx evaluatePolicy:laPolicy localizedReason:reason reply:^(BOOL success, NSError *error) {
        int32_t errorCode = LA_ERROR_SUCCESS;
        if (error) {
            errorCode = (int32_t)error.code;
        } else if (!success) {
            errorCode = LA_ERROR_AUTHENTICATION_FAILED;
        }
        completion(success ? true : false, errorCode);
    }];
}

BiometryType LAContextGetBiometryType(LAContextRef context) {
    if (!context) return BIOMETRY_TYPE_NONE;
    
    LAContext *ctx = (__bridge LAContext *)context;
    LABiometryType type = ctx.biometryType;
    
    switch (type) {
        case LABiometryTypeTouchID:
            return BIOMETRY_TYPE_TOUCH_ID;
        case LABiometryTypeFaceID:
            return BIOMETRY_TYPE_FACE_ID;
        case LABiometryTypeOpticID:
            return BIOMETRY_TYPE_OPTIC_ID;
        default:
            return BIOMETRY_TYPE_NONE;
    }
}

// MARK: - Secure Enclave Key Generation

SecKeyRef SecKeyGenerateSecureEnclaveKey(const char* tag, bool biometricRequired, int32_t* errorCode) {
    if (!tag) {
        if (errorCode) *errorCode = LA_ERROR_INVALID_CONTEXT;
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
    
    if (errorCode) *errorCode = LA_ERROR_SUCCESS;
    return (__bridge_retained SecKeyRef)privateKey;
}

void SecKeyRelease(SecKeyRef key) {
    if (key) {
        SecKeyRef k = (__bridge_transfer SecKeyRef)key;
        (void)k; // ARC handles release for NSObject, but SecKey is CFType
        CFRelease(k);
    }
}

SecKeyRef SecKeyCopyPublicKey(SecKeyRef privateKey) {
    if (!privateKey) return NULL;
    
    SecKeyRef key = (__bridge SecKeyRef)privateKey;
    SecKeyRef publicKey = SecKeyCopyPublicKey(key);
    
    if (publicKey) {
        return (__bridge_retained SecKeyRef)publicKey;
    }
    return NULL;
}

NSDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, int32_t* errorCode) {
    if (!key) {
        if (errorCode) *errorCode = LA_ERROR_INVALID_CONTEXT;
        return NULL;
    }
    
    SecKeyRef k = (__bridge SecKeyRef)key;
    CFErrorRef error = NULL;
    CFDataRef data = SecKeyCopyExternalRepresentation(k, &error);
    
    if (error) {
        if (errorCode) *errorCode = (int32_t)CFErrorGetCode(error);
        CFRelease(error);
        return NULL;
    }
    
    if (errorCode) *errorCode = LA_ERROR_SUCCESS;
    return (__bridge_retained NSDataRef)data;
}

// MARK: - Signing

NSDataRef SecKeyCreateSignature(SecKeyRef key, const uint8_t* data, size_t dataLen, int32_t* errorCode) {
    if (!key || !data || dataLen == 0) {
        if (errorCode) *errorCode = LA_ERROR_INVALID_CONTEXT;
        return NULL;
    }
    
    SecKeyRef k = (__bridge SecKeyRef)key;
    NSData *dataToSign = [NSData dataWithBytes:data length:dataLen];
    
    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(
        k,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)dataToSign,
        &error
    );
    
    if (error) {
        if (errorCode) *errorCode = (int32_t)CFErrorGetCode(error);
        CFRelease(error);
        return NULL;
    }
    
    if (errorCode) *errorCode = LA_ERROR_SUCCESS;
    return (__bridge_retained NSDataRef)signature;
}

// MARK: - NSString Helpers

NSStringRef NSStringCreateWithUTF8(const char* str) {
    if (!str) return NULL;
    NSString *nsstr = [NSString stringWithUTF8String:str];
    return (__bridge_retained NSStringRef)nsstr;
}

const char* NSStringGetUTF8(NSStringRef str) {
    if (!str) return NULL;
    NSString *nsstr = (__bridge NSString *)str;
    return [nsstr UTF8String];
}

void NSStringRelease(NSStringRef str) {
    if (str) {
        NSString *nsstr = (__bridge_transfer NSString *)str;
        (void)nsstr; // ARC handles release
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
        NSData *d = (__bridge_transfer NSData *)data;
        (void)d; // ARC handles release
    }
}

// MARK: - Keychain Storage

bool StoreCredentialInKeychain(const char* tag, SecKeyRef privateKey, int32_t* errorCode) {
    // Key is already stored in keychain via kSecAttrIsPermanent during generation
    // This function is mainly for additional metadata storage if needed
    (void)tag;
    (void)privateKey;
    if (errorCode) *errorCode = LA_ERROR_SUCCESS;
    return true;
}

SecKeyRef LoadCredentialFromKeychain(const char* tag, int32_t* errorCode) {
    if (!tag) {
        if (errorCode) *errorCode = LA_ERROR_INVALID_CONTEXT;
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
    
    if (errorCode) *errorCode = LA_ERROR_SUCCESS;
    return (__bridge_retained SecKeyRef)key;
}

bool DeleteCredentialFromKeychain(const char* tag, int32_t* errorCode) {
    if (!tag) {
        if (errorCode) *errorCode = LA_ERROR_INVALID_CONTEXT;
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
    
    if (errorCode) *errorCode = LA_ERROR_SUCCESS;
    return true;
}

// MARK: - Utility

const char* GetErrorMessage(int32_t errorCode) {
    NSString *message = nil;
    
    switch (errorCode) {
        case LA_ERROR_SUCCESS:
            message = @"Success";
            break;
        case LA_ERROR_AUTHENTICATION_FAILED:
            message = @"Authentication failed";
            break;
        case LA_ERROR_USER_CANCEL:
            message = @"User cancelled";
            break;
        case LA_ERROR_USER_FALLBACK:
            message = @"User chose to use fallback";
            break;
        case LA_ERROR_BIOMETRY_NOT_AVAILABLE:
            message = @"Biometry is not available on this device";
            break;
        case LA_ERROR_BIOMETRY_NOT_ENROLLED:
            message = @"No biometric credentials are enrolled";
            break;
        case LA_ERROR_BIOMETRY_LOCKOUT:
            message = @"Biometry is locked out";
            break;
        case LA_ERROR_INVALID_CONTEXT:
            message = @"Invalid context";
            break;
        case LA_ERROR_NOT_INTERACTIVE:
            message = @"Not interactive";
            break;
        case LA_ERROR_WATCH_NOT_AVAILABLE:
            message = @"Apple Watch is not available";
            break;
        case LA_ERROR_PASSCODE_NOT_SET:
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
