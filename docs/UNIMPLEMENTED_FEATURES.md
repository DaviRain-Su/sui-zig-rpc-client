# Unimplemented Features & TODOs

## Overview

This document tracks features that are partially implemented, stubbed, or not yet started in the Sui Zig CLI.

## Critical Path (High Priority)

### 1. Transaction Signing (tx_signer.zig)

**Status**: Placeholder implementation only

**What's Missing**:
- [ ] Actual Ed25519 public key derivation from private key
- [ ] Actual Ed25519 signing using proper cryptography
- [ ] Blake2b-256 hashing implementation
- [ ] BIP-39 mnemonic to seed conversion

**Current State**:
```zig
// TODO: Implement actual Ed25519 signing
// For now, we create a placeholder signature
```

**Impact**: Cannot sign and submit transactions to the network

### 2. Secure Enclave Key Generation (macOS)

**Status**: Works in test program but not in CLI

**What's Missing**:
- [ ] Proper code signing with entitlements for CLI binary
- [ ] Secure Enclave key generation in `passkey create`
- [ ] Keychain storage integration

**Current State**: Touch ID authentication works, but key generation fails with error -34018 (missing entitlements)

**Impact**: Cannot create actual Passkey credentials in CLI

### 3. WebSocket Subscriptions

**Status**: Placeholder only

**What's Missing**:
- [ ] WebSocket client implementation
- [ ] Event subscription handling
- [ ] Real-time notification delivery

**Current State**: `subscribe` command exists but uses simulated data

**Impact**: Cannot subscribe to real-time events

## Medium Priority

### 4. Linux WebAuthn Support

**Status**: Not implemented

**What's Missing**:
- [ ] libfido2 integration
- [ ] USB HID device detection
- [ ] YubiKey/hardware key support

**Current State**: Only macOS Touch ID is implemented

**Impact**: Linux users cannot use Passkey features

### 5. Caching System

**Status**: Not implemented

**What's Missing**:
- [ ] Object metadata cache
- [ ] Transaction result cache
- [ ] Cache invalidation strategy

**Current State**: "Caching not implemented in this version"

**Impact**: Repeated RPC calls for same data

### 6. Transaction Placeholder Resolution

**Status**: Partially implemented

**What's Missing**:
- [ ] Resolve all inferable placeholders before execution
- [ ] Better auto-selection for complex DeFi transactions

**Current State**: Some placeholders require manual input

**Impact**: Some transactions need manual editing before execution

## Lower Priority

### 7. Advanced Wallet Features

**Status**: CLI commands exist but limited functionality

**What's Missing**:
- [ ] Full wallet lifecycle management
- [ ] Request state persistence
- [ ] Session delegation
- [ ] Policy enforcement

### 8. GraphQL Integration

**Status**: Basic command exists

**What's Missing**:
- [ ] Full GraphQL query support
- [ ] Query templates
- [ ] Response parsing

### 9. Plugin System

**Status**: Framework exists, no real plugins

**What's Missing**:
- [ ] Dynamic plugin loading
- [ ] Plugin API
- [ ] Example plugins

### 10. REPL / Interactive Mode

**Status**: Basic framework exists

**What's Missing**:
- [ ] Command history
- [ ] Tab completion
- [ ] Syntax highlighting

## Completed Features ✅

- [x] Touch ID authentication prompt
- [x] Platform detection (macOS/Linux)
- [x] Basic CLI structure with 40+ commands
- [x] RPC client with HTTP/HTTPS support
- [x] Transaction building framework
- [x] Move function calling
- [x] Object discovery and selection
- [x] Gas estimation
- [x] Configuration management
- [x] Output formatting (human/json/csv)

## Next Steps Priority

1. **Implement Ed25519 signing** - Required for transaction submission
2. **Fix Secure Enclave key generation** - Required for Passkey credentials
3. **Add WebSocket support** - Required for real-time subscriptions
4. **Add Linux WebAuthn** - Platform parity
5. **Implement caching** - Performance improvement

## How to Contribute

See `docs/CONTRIBUTING.md` for contribution guidelines.

Priority areas for external contributors:
- Ed25519 cryptography implementation
- Linux libfido2 integration
- WebSocket client
- Plugin system
