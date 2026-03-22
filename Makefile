# Sui Zig RPC Client - Makefile
# Simplified build commands for common tasks

.PHONY: all build test test-fast clean fmt check install help

# Default target
all: build

# Build the project
build:
	@echo "Building Sui Zig RPC Client..."
	zig build

# Build with WebAuthn support (macOS only)
build-webauthn:
	@echo "Building with WebAuthn support..."
	zig build -Dwebauthn=true

# Run all tests
test:
	@echo "Running all tests..."
	zig build test --summary all

# Run only Zig unit tests (faster)
test-fast:
	@echo "Running Zig unit tests..."
	zig build test -Dskip-move-tests

# Run Move contract tests only
test-move:
	@echo "Running Move contract tests..."
	zig build move-fixture-test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf .zig-cache zig-out
	find fixtures/move -name "build" -type d -exec rm -rf {} + 2>/dev/null || true

# Format all Zig code
fmt:
	@echo "Formatting Zig code..."
	zig fmt src/

# Check formatting without modifying
fmt-check:
	@echo "Checking code formatting..."
	zig fmt --check src/

# Run linting and checks
check: fmt-check
	@echo "Running static analysis..."
	zig build test 2>&1 | grep -E "error|warning" || echo "No issues found"

# Install binary to local bin
install: build
	@echo "Installing to ~/.local/bin..."
	mkdir -p ~/.local/bin
	cp zig-out/bin/sui-zig-rpc-client ~/.local/bin/
	@echo "Installed. Make sure ~/.local/bin is in your PATH"

# Uninstall binary
uninstall:
	@echo "Uninstalling from ~/.local/bin..."
	rm -f ~/.local/bin/sui-zig-rpc-client

# Build release binary
release:
	@echo "Building release binary..."
	zig build -Doptimize=ReleaseFast
	@echo "Release binary: zig-out/bin/sui-zig-rpc-client"

# Build for multiple targets (requires cross-compilation setup)
release-all:
	@echo "Building for multiple targets..."
	zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu
	zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos
	zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos

# Show help
help:
	@echo "Sui Zig RPC Client - Available Commands"
	@echo ""
	@echo "Build Commands:"
	@echo "  make build          - Build the project (default)"
	@echo "  make build-webauthn - Build with WebAuthn support (macOS)"
	@echo "  make release        - Build optimized release binary"
	@echo ""
	@echo "Test Commands:"
	@echo "  make test           - Run all tests (Zig + Move)"
	@echo "  make test-fast      - Run only Zig unit tests"
	@echo "  make test-move      - Run only Move contract tests"
	@echo ""
	@echo "Code Quality:"
	@echo "  make fmt            - Format all Zig code"
	@echo "  make fmt-check      - Check formatting without changes"
	@echo "  make check          - Run all checks (format + test)"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean          - Remove build artifacts"
	@echo "  make install        - Install binary to ~/.local/bin"
	@echo "  make uninstall      - Remove installed binary"
	@echo ""
	@echo "Help:"
	@echo "  make help           - Show this help message"
