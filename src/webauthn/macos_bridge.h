// macOS WebAuthn Bridge Header
// Objective-C interface for LocalAuthentication and Secure Enclave

#ifndef MACOS_BRIDGE_H
#define MACOS_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types
typedef void* LAContextRef;
typedef void* SecKeyRef;
typedef void* NSErrorRef;
typedef void* NSStringRef;
typedef void* NSDataRef;
typedef void* NSDictionaryRef;

// Biometric types
typedef enum {
    BIOMETRY_TYPE_NONE = 0,
    BIOMETRY_TYPE_TOUCH_ID = 1,
    BIOMETRY_TYPE_FACE_ID = 2,
    BIOMETRY_TYPE_OPTIC_ID = 3
} BiometryType;

// Policy for authentication
typedef enum {
    POLICY_DEVICE_OWNER_AUTHENTICATION = 1,
    POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS = 2,
    POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_WATCH = 3
} LAPolicy;

// Error codes
typedef enum {
    LA_ERROR_SUCCESS = 0,
    LA_ERROR_AUTHENTICATION_FAILED = -1,
    LA_ERROR_USER_CANCEL = -2,
    LA_ERROR_USER_FALLBACK = -3,
    LA_ERROR_BIOMETRY_NOT_AVAILABLE = -4,
    LA_ERROR_BIOMETRY_NOT_ENROLLED = -5,
    LA_ERROR_BIOMETRY_LOCKOUT = -6,
    LA_ERROR_INVALID_CONTEXT = -7,
    LA_ERROR_NOT_INTERACTIVE = -8,
    LA_ERROR_WATCH_NOT_AVAILABLE = -9,
    LA_ERROR_BIOMETRY_NOT_PREFERRED = -10,
    LA_ERROR_CREDENTIAL_SET_EXPIRED = -11,
    LA_ERROR_PASSCODE_NOT_SET = -12,
    LA_ERROR_SYSTEM_CANCEL = -13,
    LA_ERROR_INVALID_DIMENSIONS = -14,
    LA_ERROR_OTHER = -99
} LAError;

// LAContext functions
LAContextRef LAContextCreate(void);
void LAContextRelease(LAContextRef context);
bool LAContextCanEvaluatePolicy(LAContextRef context, LAPolicy policy, int32_t* errorCode);
void LAContextEvaluatePolicy(LAContextRef context, LAPolicy policy, const char* localizedReason, 
                              void (*completion)(bool success, int32_t errorCode));
BiometryType LAContextGetBiometryType(LAContextRef context);

// Secure Enclave key generation
SecKeyRef SecKeyGenerateSecureEnclaveKey(const char* tag, bool biometricRequired, int32_t* errorCode);
void SecKeyRelease(SecKeyRef key);
SecKeyRef SecKeyCopyPublicKey(SecKeyRef privateKey);
NSDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, int32_t* errorCode);

// Signing
NSDataRef SecKeyCreateSignature(SecKeyRef key, const uint8_t* data, size_t dataLen, int32_t* errorCode);

// NSString helpers
NSStringRef NSStringCreateWithUTF8(const char* str);
const char* NSStringGetUTF8(NSStringRef str);
void NSStringRelease(NSStringRef str);

// NSData helpers
size_t NSDataGetLength(NSDataRef data);
const uint8_t* NSDataGetBytes(NSDataRef data);
void NSDataRelease(NSDataRef data);

// Keychain storage
bool StoreCredentialInKeychain(const char* tag, SecKeyRef privateKey, int32_t* errorCode);
SecKeyRef LoadCredentialFromKeychain(const char* tag, int32_t* errorCode);
bool DeleteCredentialFromKeychain(const char* tag, int32_t* errorCode);

// Utility
const char* GetErrorMessage(int32_t errorCode);
void FreeString(const char* str);

#ifdef __cplusplus
}
#endif

#endif // MACOS_BRIDGE_H
