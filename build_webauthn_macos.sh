#!/bin/bash
# Build script for macOS WebAuthn support with Objective-C bindings

set -e

echo "==================================="
echo "Building Sui Zig CLI with WebAuthn"
echo "==================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create build directory
BUILD_DIR=".build/macos_webauthn"
mkdir -p "$BUILD_DIR"

# Check for required tools
echo "Checking prerequisites..."

if ! command -v clang &> /dev/null; then
    echo -e "${RED}Error: clang not found. Install Xcode Command Line Tools.${NC}"
    echo "Run: xcode-select --install"
    exit 1
fi

if ! command -v zig &> /dev/null; then
    echo -e "${RED}Error: zig not found.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo ""

# Step 1: Compile Objective-C bridge
echo "Step 1: Compiling Objective-C bridge..."
echo "----------------------------------------"

clang -c src/webauthn/macos_bridge.m \
    -o "$BUILD_DIR/macos_bridge.o" \
    -framework LocalAuthentication \
    -framework Security \
    -framework Foundation \
    -fobjc-arc \
    -mmacosx-version-min=10.15 \
    -I. \
    -Wall \
    -Wextra \
    2>&1 | tee "$BUILD_DIR/compile.log"

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Objective-C compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Objective-C compiled successfully${NC}"
echo ""

# Step 2: Create static library
echo "Step 2: Creating static library..."
echo "-----------------------------------"

ar rcs "$BUILD_DIR/libmacos_webauthn.a" "$BUILD_DIR/macos_bridge.o"
ranlib "$BUILD_DIR/libmacos_webauthn.a"

echo -e "${GREEN}✓ Static library created${NC}"
echo "   Library: $BUILD_DIR/libmacos_webauthn.a"
echo "   Size: $(ls -lh "$BUILD_DIR/libmacos_webauthn.a" | awk '{print $5}')"
echo ""

# Step 3: Build Zig project with WebAuthn
echo "Step 3: Building Zig project..."
echo "--------------------------------"

# Create a custom build.zig for WebAuthn build
cat > "$BUILD_DIR/build_webauthn.zig" << 'EOF'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sui-zig-webauthn",
        .root_source_file = b.path("../../src/main_v2.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add WebAuthn static library
    exe.addObjectFile(.{ .cwd_relative = ".build/macos_webauthn/libmacos_webauthn.a" });

    // Link Apple frameworks
    exe.linkFramework("LocalAuthentication");
    exe.linkFramework("Security");
    exe.linkFramework("Foundation");

    // macOS version
    exe.root_module.addCMacro("MACOSX_DEPLOYMENT_TARGET", "10.15");

    b.installArtifact(exe);
}
EOF

cd "$BUILD_DIR"
zig build -f ../../build.zig 2>&1 | tee -a build.log

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Zig build failed${NC}"
    cd ../..
    exit 1
fi

cd ../..

echo -e "${GREEN}✓ Zig build completed${NC}"
echo ""

# Step 4: Copy final binary
echo "Step 4: Finalizing build..."
echo "----------------------------"

if [ -f "zig-out/bin/sui-zig-webauthn" ]; then
    cp "zig-out/bin/sui-zig-webauthn" "$BUILD_DIR/sui-zig-webauthn"
    echo -e "${GREEN}✓ Binary created${NC}"
    echo "   Location: $BUILD_DIR/sui-zig-webauthn"
    echo "   Size: $(ls -lh "$BUILD_DIR/sui-zig-webauthn" | awk '{print $5}')"
elif [ -f ".zig-cache/o/*/sui-zig-webauthn" ]; then
    find .zig-cache -name "sui-zig-webauthn" -type f -exec cp {} "$BUILD_DIR/" \;
    echo -e "${GREEN}✓ Binary created${NC}"
    echo "   Location: $BUILD_DIR/sui-zig-webauthn"
else
    echo -e "${YELLOW}⚠ Binary location unknown, checking...${NC}"
    find . -name "sui-zig-webauthn" -type f 2>/dev/null | head -5
fi

echo ""
echo "==================================="
echo -e "${GREEN}Build completed successfully!${NC}"
echo "==================================="
echo ""
echo "Next steps:"
echo "  1. Test WebAuthn support:"
echo "     $BUILD_DIR/sui-zig-webauthn passkey platform"
echo ""
echo "  2. Create a Passkey (requires Touch ID):"
echo "     $BUILD_DIR/sui-zig-webauthn passkey create --name 'Test'"
echo ""
echo "  3. Run full test suite:"
echo "     ./test_webauthn_macos.sh"
echo ""
