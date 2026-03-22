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
typedef void* BridgeSecKeyRef;
typedef void* NSErrorRef;
typedef void* NSStringRef;
typedef void* NSDataRef;
typedef void* NSDictionaryRef;

// Biometric types
typedef enum {
    BRIDGE_BIOMETRY_TYPE_NONE = 0,
    BRIDGE_BIOMETRY_TYPE_TOUCH_ID = 1,
    BRIDGE_BIOMETRY_TYPE_FACE_ID = 2,
    BRIDGE_BIOMETRY_TYPE_OPTIC_ID = 3
} BridgeBiometryType;

// Policy for authentication
typedef enum {
    BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION = 1,
    BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS = 2,
    BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_WATCH = 3
} BridgeLAPolicy;

// Error codes
typedef enum {
    BRIDGE_LA_ERROR_SUCCESS = 0,
    BRIDGE_LA_ERROR_AUTHENTICATION_FAILED = -1,
    BRIDGE_LA_ERROR_USER_CANCEL = -2,
    BRIDGE_LA_ERROR_USER_FALLBACK = -3,
    BRIDGE_LA_ERROR_BIOMETRY_NOT_AVAILABLE = -4,
    BRIDGE_LA_ERROR_BIOMETRY_NOT_ENROLLED = -5,
    BRIDGE_LA_ERROR_BIOMETRY_LOCKOUT = -6,
    BRIDGE_LA_ERROR_INVALID_CONTEXT = -7,
    BRIDGE_LA_ERROR_NOT_INTERACTIVE = -8,
    BRIDGE_LA_ERROR_WATCH_NOT_AVAILABLE = -9,
    BRIDGE_LA_ERROR_BIOMETRY_NOT_PREFERRED = -10,
    BRIDGE_LA_ERROR_CREDENTIAL_SET_EXPIRED = -11,
    BRIDGE_LA_ERROR_PASSCODE_NOT_SET = -12,
    BRIDGE_LA_ERROR_SYSTEM_CANCEL = -13,
    BRIDGE_LA_ERROR_INVALID_DIMENSIONS = -14,
    BRIDGE_LA_ERROR_OTHER = -99
} BridgeLAError;

// LAContext functions
LAContextRef LAContextCreate(void);
void LAContextRelease(LAContextRef context);
bool LAContextCanEvaluatePolicy(LAContextRef context, BridgeLAPolicy policy, int32_t* errorCode);
void LAContextEvaluatePolicy(LAContextRef context, BridgeLAPolicy policy, const char* localizedReason, 
                              void (*completion)(bool success, int32_t errorCode));
BridgeBiometryType LAContextGetBiometryType(LAContextRef context);

// Secure Enclave key generation
BridgeSecKeyRef BridgeSecKeyGenerateSecureEnclaveKey(const char* tag, bool biometricRequired, int32_t* errorCode);
void BridgeSecKeyRelease(BridgeSecKeyRef key);
BridgeSecKeyRef BridgeSecKeyCopyPublicKey(BridgeSecKeyRef privateKey);
NSDataRef BridgeSecKeyCopyExternalRepresentation(BridgeSecKeyRef key, int32_t* errorCode);

// Signing
NSDataRef BridgeSecKeyCreateSignature(BridgeSecKeyRef key, const uint8_t* data, size_t dataLen, int32_t* errorCode);

// NSString helpers
NSStringRef NSStringCreateWithUTF8(const char* str);
const char* NSStringGetUTF8(NSStringRef str);
void NSStringRelease(NSStringRef str);

// NSData helpers
size_t NSDataGetLength(NSDataRef data);
const uint8_t* NSDataGetBytes(NSDataRef data);
void NSDataRelease(NSDataRef data);

// Keychain storage
bool StoreCredentialInKeychain(const char* tag, BridgeSecKeyRef privateKey, int32_t* errorCode);
BridgeSecKeyRef LoadCredentialFromKeychain(const char* tag, int32_t* errorCode);
bool DeleteCredentialFromKeychain(const char* tag, int32_t* errorCode);

// Utility
const char* GetErrorMessage(int32_t errorCode);
void FreeString(const char* str);

#ifdef __cplusplus
}
#endif

#endif // MACOS_BRIDGE_H
