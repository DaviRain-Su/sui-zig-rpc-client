# Browser WebAuthn Integration Plan

## Overview

Browser WebAuthn allows using hardware security keys (YubiKey) and platform authenticators (Touch ID/Face ID on iPhone/iPad) through the browser's WebAuthn API.

## How It Works

### Tempo Wallet Approach

Tempo Wallet and similar apps use this flow:

1. **CLI generates QR code or URL** containing challenge
2. **User scans QR with phone** or opens URL on device
3. **Browser webpage uses WebAuthn API** to create credential/sign
4. **Result is sent back** to CLI via WebSocket, QR polling, or manual entry

### Implementation Options

#### Option 1: Local HTTP Server (Complex)
- CLI starts local HTTP server
- Opens browser with `http://localhost:PORT`
- Browser uses WebAuthn and POSTs result back
- CLI receives result and closes server

**Pros:**
- Fully automated
- Good UX

**Cons:**
- Requires HTTP server implementation
- Firewall/port issues
- Complex error handling

#### Option 2: File-based (Simple, Current)
- CLI generates HTML file
- Opens browser with `file://` URL
- User authenticates and downloads JSON file
- CLI polls for file appearance

**Pros:**
- Simple to implement
- No network required
- Works offline

**Cons:**
- Manual file movement
- Less polished UX

#### Option 3: QR Code + Phone (Best for Mobile)
- CLI generates QR code with challenge
- User scans with phone
- Phone opens webpage and authenticates
- Result sent via cloud/WebSocket back to CLI

**Pros:**
- Mobile-friendly
- Can use phone's Face ID/Touch ID
- Hardware key support

**Cons:**
- Requires cloud service or WebSocket server
- More complex infrastructure

## Recommended Approach

For this CLI, **Option 2 (File-based)** is recommended because:

1. ✅ Simple to implement
2. ✅ No external dependencies
3. ✅ Works completely offline
4. ✅ Supports all authenticator types
5. ✅ Free (no cloud service needed)

## User Flow

```
$ sui-zig passkey create-browser --name "My YubiKey"

=== Create Passkey via Browser ===

Opening browser with WebAuthn interface...

Please:
  1. Click "Create Passkey" in the browser
  2. Authenticate with your security key or Touch ID
  3. Download the credential file
  4. Move it to: ~/.sui-zig/keystore/

Waiting for credential file... (timeout: 2 minutes)

✓ Credential received!
  ID: sui-passkey-My YubiKey-1234567890
  Type: YubiKey 5 NFC (USB + NFC)
  Public Key: 65 bytes (P-256)
  Sui Address: 0x2a2d17965d701ef32577d8253d66462f7cb11fa7
```

## HTML Interface

The generated HTML page provides:

- Beautiful, modern UI
- Support for multiple authenticator types:
  - 🔑 YubiKey (USB/NFC)
  - 👆 Touch ID (MacBook)
  - 😊 Face ID (iPhone/iPad)
  - 🔐 Windows Hello
- Clear instructions
- Error handling
- Automatic file download

## Technical Details

### WebAuthn Parameters

```javascript
const publicKey = {
  challenge: randomBytes(32),
  rp: { name: "Sui CLI", id: "sui-cli.local" },
  user: { id: randomBytes(16), name: "My Key", displayName: "My Key" },
  pubKeyCredParams: [{ alg: -7, type: "public-key" }], // ES256 (P-256)
  authenticatorSelection: {
    userVerification: "required"
  }
};
```

### Credential Format

```json
{
  "requestId": "abc123...",
  "id": "base64-credential-id",
  "rawId": [1, 2, 3, ...],
  "type": "public-key",
  "response": {
    "clientDataJSON": [123, 34, 116, ...],
    "attestationObject": [161, 104, ...]
  }
}
```

## Security Considerations

1. **Challenge/Response**: Proper challenge generation prevents replay attacks
2. **Origin Validation**: Browser enforces origin (sui-cli.local)
3. **User Verification**: Required (biometric/PIN)
4. **Attestation**: Optional, can verify authenticator type

## Future Enhancements

1. **QR Code**: Generate QR for mobile authentication
2. **WebSocket**: Real-time communication instead of file polling
3. **Cloud Relay**: Use relay service for remote signing
4. **Push Notification**: Push to phone for authentication

## References

- [WebAuthn Spec](https://www.w3.org/TR/webauthn-2/)
- [Tempo Wallet](https://tempo.finance/)
- [YubiKey WebAuthn](https://developers.yubico.com/WebAuthn/)
