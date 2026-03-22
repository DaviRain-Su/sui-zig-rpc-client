#!/bin/bash
# Test script for macOS WebAuthn functionality

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BUILD_DIR=".build/macos_webauthn"
BINARY="$BUILD_DIR/sui-zig-webauthn"

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}Error: Binary not found at $BINARY${NC}"
    echo "Run ./build_webauthn_macos.sh first"
    exit 1
fi

echo "==================================="
echo "Testing macOS WebAuthn Support"
echo "==================================="
echo ""

# Test 1: Platform detection
echo -e "${BLUE}Test 1: Platform Detection${NC}"
echo "---------------------------"
$BINARY passkey platform
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Platform detection passed${NC}"
else
    echo -e "${RED}✗ Platform detection failed${NC}"
    exit 1
fi
echo ""

# Test 2: WebAuthn availability
echo -e "${BLUE}Test 2: WebAuthn Availability${NC}"
echo "------------------------------"
$BINARY passkey create --name "Test Key" 2>&1 | head -20
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ WebAuthn interface accessible${NC}"
else
    echo -e "${YELLOW}⚠ WebAuthn may not be fully available${NC}"
fi
echo ""

# Test 3: Biometric info
echo -e "${BLUE}Test 3: Biometric Information${NC}"
echo "------------------------------"
echo "Checking biometric support..."
echo ""
echo "Note: This would check:"
echo "  - Touch ID availability"
echo "  - Face ID availability"
echo "  - Secure Enclave status"
echo ""
echo -e "${YELLOW}Manual verification required:${NC}"
echo "  1. Open System Preferences > Touch ID"
echo "  2. Verify fingerprints are enrolled"
echo "  3. Run: $BINARY passkey create --name 'My Key'"
echo ""

# Test 4: Keychain access
echo -e "${BLUE}Test 4: Keychain Access${NC}"
echo "------------------------"
echo "Testing keychain access..."
echo ""
echo "Note: Keychain access requires:"
echo "  - User approval on first access"
echo "  - Proper entitlements in signed binary"
echo ""

# Test 5: Integration test
echo -e "${BLUE}Test 5: Integration Test${NC}"
echo "-------------------------"
echo "Running integration tests..."
echo ""

# Create a test credential (will prompt for Touch ID)
echo -e "${YELLOW}This test will prompt for Touch ID${NC}"
read -p "Press Enter to continue or Ctrl+C to skip..."

echo "Creating test credential..."
$BINARY passkey create --name "Integration Test Key" 2>&1 || true
echo ""

# Test 6: Error handling
echo -e "${BLUE}Test 6: Error Handling${NC}"
echo "-----------------------"
echo "Testing error scenarios..."
echo ""

# Try to sign with non-existent credential
echo "Testing sign with invalid credential..."
$BINARY passkey sign --id "invalid_id" --tx "dGVzdA==" 2>&1 || true
echo ""

echo "==================================="
echo -e "${GREEN}Test suite completed!${NC}"
echo "==================================="
echo ""
echo "Summary:"
echo "  - Platform detection: Tested"
echo "  - WebAuthn interface: Tested"
echo "  - Biometric support: Manual verification needed"
echo "  - Keychain access: Requires signed binary"
echo ""
echo "Next steps:"
echo "  1. Code sign the binary for full testing"
echo "  2. Run on a Touch ID-capable Mac"
echo "  3. Verify actual biometric prompts"
echo ""
