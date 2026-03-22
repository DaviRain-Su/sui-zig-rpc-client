# Building WebAuthn Support on macOS

## Overview

This document describes how to build the Sui Zig CLI with native WebAuthn support on macOS using the LocalAuthentication framework and Secure Enclave.

## Prerequisites

- macOS 10.15+ (Catalina or later)
- Xcode Command Line Tools
- Zig 0.15.2+
- Touch ID capable Mac (for testing Touch ID)

## Components

### Objective-C Bridge

The bridge consists of:
- `macos_bridge.h` - C header for Objective-C bindings
- `macos_bridge.m` - Objective-C implementation
- `macos_impl.zig` - Zig wrapper using the C bindings

### Features

- **Touch ID / Face ID**: Biometric authentication
- **Secure Enclave**: Hardware key storage
- **Keychain Integration**: Persistent credential storage
- **P-256 ECDSA**: Elliptic curve signatures

## Building

### Step 1: Compile Objective-C Bridge

```bash
# Compile the Objective-C bridge to a static library
clang -c src/webauthn/macos_bridge.m \
    -o macos_bridge.o \
    -framework LocalAuthentication \
    -framework Security \
    -framework Foundation \
    -fobjc-arc

# Create static library
ar rcs libmacos_webauthn.a macos_bridge.o
```

### Step 2: Build Zig Project

```bash
# Build with WebAuthn support
zig build -Dwebauthn \
    --library libmacos_webauthn.a \
    -framework LocalAuthentication \
    -framework Security \
    -framework Foundation
```

### Build Script

Create `build_macos_webauthn.sh`:

```bash
#!/bin/bash

set -e

echo "Building macOS WebAuthn bridge..."

# Compile Objective-C
clang -c src/webauthn/macos_bridge.m \
    -o .zig-cache/macos_bridge.o \
    -framework LocalAuthentication \
    -framework Security \
    -framework Foundation \
    -fobjc-arc \
    -I.

# Create static library
ar rcs .zig-cache/libmacos_webauthn.a .zig-cache/macos_bridge.o

echo "Building Zig project..."
zig build \
    -Dwebauthn \
    --library .zig-cache/libmacos_webauthn.a \
    -framework LocalAuthentication \
    -framework Security \
    -framework Foundation

echo "Build complete!"
```

## Usage

### Check Platform Support

```bash
./sui-zig-rpc-client-v2 passkey platform
```

Output:
```
=== WebAuthn Platform Info ===

Current Platform: macos

macOS WebAuthn Support:
  - Touch ID: MacBook Pro/Air with Touch ID
  - Secure Enclave: Hardware key storage
  - LocalAuthentication: Biometric API

Implementation:
  - Objective-C runtime bindings
  - LAContext for biometric auth
  - SecKey for key management
```

### Create Passkey

```bash
./sui-zig-rpc-client-v2 passkey create --name "My Sui Key"
```

This will:
1. Prompt for Touch ID / password
2. Generate P-256 keypair in Secure Enclave
3. Store credential in keychain
4. Display credential ID

### Sign Transaction

```bash
./sui-zig-rpc-client-v2 passkey sign \
    --id <credential_id> \
    --tx <transaction_bytes>
```

This will:
1. Load credential from keychain
2. Prompt for Touch ID
3. Sign transaction with private key
4. Return signature

## Architecture

### Data Flow

```
Zig Code
    |
    v
macos_impl.zig (Zig wrapper)
    |
    v
macos_bridge.h / .m (Objective-C)
    |
    v
LocalAuthentication.framework
    |
    v
Secure Enclave (Hardware)
```

### Key Generation

1. `SecKeyGenerateSecureEnclaveKey()` creates P-256 keypair
2. Private key stored in Secure Enclave (never exported)
3. Public key exported for address derivation
4. Credential metadata stored in keychain

### Signing Process

1. User calls `sign()` with transaction hash
2. `LAContextEvaluatePolicy()` prompts for biometric
3. On success, `SecKeyCreateSignature()` signs in Secure Enclave
4. Signature returned to caller

## Security

### Private Key Protection

- Private keys never leave Secure Enclave
- Biometric authentication required for each use
- Keys are non-extractable
- Hardware-backed encryption

### Keychain Storage

```
Keychain Item:
  - kSecClass: kSecClassKey
  - kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom (P-256)
  - kSecAttrTokenID: kSecAttrTokenIDSecureEnclave
  - kSecAttrAccessControl: kSecAccessControlBiometryCurrentSet
  - kSecAttrApplicationTag: Credential ID
```

## Troubleshooting

### "Biometry not available"

- Check if Touch ID is enabled in System Preferences
- Ensure at least one fingerprint is enrolled
- On Macs without Touch ID, password will be used

### "Key generation failed"

- Verify Secure Enclave is available (T2 chip or Apple Silicon)
- Check code signing is enabled
- Ensure proper entitlements

### Build errors

```bash
# Clean and rebuild
rm -rf .zig-cache
./build_macos_webauthn.sh
```

## Testing

### Unit Tests

```bash
zig build test -Dwebauthn
```

### Integration Tests

```bash
# Test biometric availability
./sui-zig-rpc-client-v2 passkey platform

# Test credential creation (requires Touch ID)
./sui-zig-rpc-client-v2 passkey create --name "Test Key"

# Test signing (requires credential)
./sui-zig-rpc-client-v2 passkey sign --id <id> --tx <tx>
```

## Limitations

- Requires macOS 10.15+ (Catalina)
- Touch ID requires compatible hardware
- Keys are device-bound (not syncable)
- No iCloud Keychain support (by design for security)

## Future Improvements

- [ ] Support for password fallback
- [ ] Key attestation verification
- [ ] Multiple credential management
- [ ] Export/backup functionality (with user consent)
- [ ] Integration with Sui Wallet standard

## References

- [LocalAuthentication Framework](https://developer.apple.com/documentation/localauthentication)
- [Secure Enclave](https://developer.apple.com/documentation/security/secure_enclave)
- [WebAuthn Spec](https://www.w3.org/TR/webauthn-2/)
- [Sui Passkey Documentation](https://docs.sui.io/concepts/cryptography/passkey)
