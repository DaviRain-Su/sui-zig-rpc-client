// Test program for macOS WebAuthn bridge
// Compile: clang test_macos_bridge.c macos_bridge.o -o test_bridge -framework LocalAuthentication -framework Security -framework Foundation

#include <stdio.h>
#include <stdbool.h>
#include "src/webauthn/macos_bridge.h"

int main() {
    printf("===================================\n");
    printf("macOS WebAuthn Bridge Test\n");
    printf("===================================\n\n");

    // Test 1: Create LAContext
    printf("Test 1: Creating LAContext...\n");
    LAContextRef context = LAContextCreate();
    if (context == NULL) {
        printf("  ✗ Failed to create LAContext\n");
        return 1;
    }
    printf("  ✓ LAContext created successfully\n\n");

    // Test 2: Check biometric availability
    printf("Test 2: Checking biometric availability...\n");
    int32_t errorCode = 0;
    bool available = LAContextCanEvaluatePolicy(
        context, 
        BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        &errorCode
    );
    
    if (available) {
        printf("  ✓ Biometric authentication is available\n");
        
        // Get biometric type
        BridgeBiometryType bioType = LAContextGetBiometryType(context);
        printf("  Biometry type: ");
        switch (bioType) {
            case BRIDGE_BIOMETRY_TYPE_NONE:
                printf("None\n");
                break;
            case BRIDGE_BIOMETRY_TYPE_TOUCH_ID:
                printf("Touch ID\n");
                break;
            case BRIDGE_BIOMETRY_TYPE_FACE_ID:
                printf("Face ID\n");
                break;
            case BRIDGE_BIOMETRY_TYPE_OPTIC_ID:
                printf("Optic ID\n");
                break;
        }
    } else {
        printf("  ✗ Biometric authentication is not available\n");
        printf("  Error code: %d\n", errorCode);
        const char* msg = GetErrorMessage(errorCode);
        printf("  Error: %s\n", msg);
        FreeString(msg);
    }
    printf("\n");

    // Test 3: Check device authentication (password fallback)
    printf("Test 3: Checking device authentication...\n");
    errorCode = 0;
    bool deviceAuth = LAContextCanEvaluatePolicy(
        context,
        BRIDGE_POLICY_DEVICE_OWNER_AUTHENTICATION,
        &errorCode
    );
    
    if (deviceAuth) {
        printf("  ✓ Device authentication is available\n");
    } else {
        printf("  ✗ Device authentication is not available\n");
        printf("  Error code: %d\n", errorCode);
    }
    printf("\n");

    // Cleanup
    LAContextRelease(context);

    printf("===================================\n");
    printf("Test completed!\n");
    printf("===================================\n");
    printf("\n");
    printf("Summary:\n");
    printf("  - LAContext creation: ✓\n");
    printf("  - Biometric detection: %s\n", available ? "✓" : "✗");
    printf("  - Device auth detection: %s\n", deviceAuth ? "✓" : "✗");
    printf("\n");

    if (!available && !deviceAuth) {
        printf("Note: WebAuthn requires either:\n");
        printf("  - Touch ID capable MacBook\n");
        printf("  - Password authentication enabled\n");
        printf("\n");
    }

    return 0;
}
