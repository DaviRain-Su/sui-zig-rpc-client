#!/bin/bash
# Setup code signing for Secure Enclave access

set -e

echo "==================================="
echo "Code Signing Setup for Sui Zig CLI"
echo "==================================="
echo ""

cd "$(dirname "$0")/.."

BINARY="./zig-out/bin/sui-zig-rpc-client-v2"
ENTITLEMENTS_FILE="scripts/sui_zig.entitlements"

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    echo "Building binary first..."
    zig build -Dwebauthn
fi

# Create minimal entitlements file for Secure Enclave
echo "Creating entitlements file..."
cat > "$ENTITLEMENTS_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Allow JIT code generation -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    
    <!-- Allow unsigned executable memory -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    
    <!-- Disable library validation -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
EOF

echo "✓ Entitlements file created"
echo ""

# Sign the binary
echo "Signing binary with entitlements..."
codesign \
    --force \
    --sign - \
    --entitlements "$ENTITLEMENTS_FILE" \
    "$BINARY"

echo "✓ Binary signed"
echo ""

# Verify signature
echo "Verifying signature..."
if codesign -vv "$BINARY" 2>&1 | grep -q "valid"; then
    echo "✓ Signature valid"
else
    echo "⚠ Signature verification had issues"
fi

echo ""
echo "==================================="
echo "✓ Code signing complete!"
echo "==================================="
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
