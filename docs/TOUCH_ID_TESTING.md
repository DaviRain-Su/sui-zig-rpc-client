# Touch ID Testing Guide

## Overview

This guide explains how to test the Touch ID / WebAuthn functionality on a real MacBook.

## Prerequisites

- macOS 10.15+ (Catalina or later)
- Touch ID capable MacBook (MacBook Pro/Air with Touch ID)
- Fingerprints enrolled in System Preferences > Touch ID

## Test Results

### Automated Tests (Completed)

```
✓ Platform: macOS
✓ LAContext: Created successfully
✓ Biometric detection: Available
  Biometry type: Touch ID 🖐️
✓ Device authentication: Available
```

### Interactive Tests (Requires GUI)

The Touch ID prompt requires a GUI environment to display the system authentication dialog. In terminal/SSH sessions, the prompt may timeout.

## Testing Touch ID

### Method 1: Terminal with GUI Access

1. **Build the test program:**
```bash
zig build-exe test_touchid.zig \
    -framework LocalAuthentication \
    -framework Security \
    -framework Foundation \
    -I src/webauthn \
    macos_bridge.o \
    -O ReleaseSafe \
    --name test_touchid
```

2. **Run the test:**
```bash
./test_touchid
```

3. **Expected behavior:**
   - You'll see "Press Enter to continue..."
   - After pressing Enter, a system Touch ID dialog should appear
   - Place your finger on the Touch ID sensor
   - The test should continue with key generation

### Method 2: Using the CLI

1. **Build with WebAuthn support:**
```bash
zig build -Dwebauthn
```

2. **Check platform:**
```bash
./zig-out/bin/sui-zig-rpc-client-v2 passkey platform
```

3. **Create a passkey (will prompt for Touch ID):**
```bash
./zig-out/bin/sui-zig-rpc-client-v2 passkey create --name "My Test Key"
```

### Method 3: Xcode Testing (Recommended)

For full GUI integration testing, create an Xcode project:

1. **Create a new Xcode project:**
   - File > New > Project
   - Select "Command Line Tool"
   - Language: C

2. **Add files:**
   - Add `macos_bridge.m` and `macos_bridge.h`
   - Add your Zig-generated C code (if using `zig translate-c`)

3. **Configure build settings:**
   - Link with LocalAuthentication.framework
   - Link with Security.framework
   - Link with Foundation.framework

4. **Run from Xcode:**
   - This ensures proper GUI context for Touch ID prompts

## Troubleshooting

### "Authentication timed out"

This usually means:
- Running in SSH session (no GUI access)
- Running in tmux/screen without proper GUI context
- Touch ID not enrolled

**Solution:** Run directly in Terminal.app or iTerm2 with GUI access.

### "Biometry not available"

Check System Preferences > Touch ID:
- Ensure at least one fingerprint is enrolled
- Ensure "Use Touch ID for:" options are enabled

### "Key generation failed"

Possible causes:
- Secure Enclave not available (very old Mac)
- Code signing issues
- Keychain access restricted

**Solution:** Try code signing the binary:
```bash
codesign -s "-" test_touchid
```

## Security Considerations

### Code Signing

For production use, code sign your binary:

```bash
# Self-sign for testing
codesign -s "-" -f test_touchid

# Or with a developer certificate
codesign -s "Developer ID Application: Your Name" test_touchid
```

### Entitlements

For App Store distribution, you may need entitlements:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.yourcompany.sui-zig</string>
    </array>
</dict>
</plist>
```

Sign with entitlements:
```bash
codesign -s "-" --entitlements entitlements.plist -f test_touchid
```

## Expected Test Output (Successful)

```
╔══════════════════════════════════════════════════════════════╗
║           Touch ID / WebAuthn Test Program                   ║
╚══════════════════════════════════════════════════════════════╝

Test 1: Platform Detection
──────────────────────────
✓ LAContext created

Test 2: Biometric Availability
──────────────────────────────
✓ Biometric authentication is available
  Biometry type: Touch ID 🖐️

Test 3: Device Authentication
─────────────────────────────
✓ Device authentication is available

Test 4: Touch ID Authentication Prompt
──────────────────────────────────────

⚠️  This test will prompt for Touch ID / Password
    Press Enter to continue...

🔐 Prompting for authentication...
   (You should see a Touch ID / Password prompt)

✓ Authentication successful! 🎉

Test 5: Secure Enclave Key Generation
─────────────────────────────────────
Generating P-256 key in Secure Enclave...
✓ Private key generated in Secure Enclave
✓ Public key exported (65 bytes)
   First bytes: 04a3b2c1...

Test 6: Sign with Touch ID
──────────────────────────
Signing test data (will prompt for Touch ID)...
✓ Signature created (71 bytes)
🎉 Touch ID signing works!

Cleaning up test key...
✓ Test key deleted

╔══════════════════════════════════════════════════════════════╗
║                      Test Summary                            ║
╚══════════════════════════════════════════════════════════════╝

✓ Platform: macOS
✓ LAContext: Created successfully
✓ Biometric detection: Available
✓ Device authentication: Available
✓ Touch ID prompt: Successful

🎉 All Touch ID tests passed!

Your MacBook is ready for WebAuthn/Passkey operations.
```

## Next Steps

After successful testing:

1. **Integrate into main CLI:** Use `passkey create` and `passkey sign` commands
2. **Add to CI/CD:** Use mock authentication for automated tests
3. **Document for users:** Explain Touch ID setup requirements

## References

- [Apple LocalAuthentication Documentation](https://developer.apple.com/documentation/localauthentication)
- [Secure Enclave Guide](https://developer.apple.com/documentation/security/secure_enclave)
- [WebAuthn Specification](https://www.w3.org/TR/webauthn-2/)
