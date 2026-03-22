#!/bin/bash
# Build, sign, and run the CLI with proper entitlements for Secure Enclave

set -e

echo "Building Sui Zig CLI with WebAuthn support..."
cd "$(dirname "$0")/.."

# Build with WebAuthn
zig build -Dwebauthn

BINARY="./zig-out/bin/sui-zig-rpc-client-v2"

# Create entitlements file
cat > /tmp/sui_zig_entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.sui-zig.cli</string>
    </array>
    <key>com.apple.developer.default-data-protection</key>
    <string>NSFileProtectionComplete</string>
</dict>
</plist>
EOF

# Sign the binary with entitlements
echo "Signing binary with entitlements..."
codesign -s "-" --entitlements /tmp/sui_zig_entitlements.plist --force "$BINARY"

# Verify signature
echo "Verifying signature..."
codesign -vv "$BINARY"

echo ""
echo "✓ Binary signed successfully!"
echo ""
echo "You can now run:"
echo "  $BINARY passkey create --name \"My Key\""
echo ""

# Optionally run the command
if [ $# -gt 0 ]; then
    echo "Running: $BINARY $@"
    echo ""
    exec "$BINARY" "$@"
fi
