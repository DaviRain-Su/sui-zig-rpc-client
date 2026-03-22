#!/bin/bash
# Wallet Demo Script

CLI="./zig-out/bin/sui-zig-rpc-client-v2"

echo "=== Sui Zig CLI - Advanced Wallet Demo ==="
echo ""

# Initialize wallet
echo "1. Initialize wallet for address 0x1234..."
$CLI wallet init 0x1234567890abcdef 2>&1 | grep -v "error(gpa)"
echo ""

# Start session
echo "2. Start session..."
$CLI wallet session start 2>&1 | grep -v "error(gpa)"
echo ""

# Check status
echo "3. Check wallet status..."
$CLI wallet status 2>&1 | grep -v "error(gpa)"
echo ""

# Check policy
echo "4. View policy..."
$CLI wallet policy 2>&1 | grep -v "error(gpa)"
echo ""

# Check transactions
echo "5. Check if transactions are allowed..."
echo "   a) Small transaction (0.001 SUI):"
$CLI wallet check 0x5678 1000000 2>&1 | grep -v "error(gpa)"
echo ""
echo "   b) Large transaction (100 SUI):"
$CLI wallet check 0x5678 100000000000 2>&1 | grep -v "error(gpa)"
echo ""

# End session
echo "6. End session..."
$CLI wallet session end 2>&1 | grep -v "error(gpa)"
echo ""

echo "=== Demo Complete ==="
