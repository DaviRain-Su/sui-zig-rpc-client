# Sui Zig RPC Client

[![Zig Version](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-140%2B%20passing-brightgreen.svg)]()

A comprehensive Sui CLI and RPC client implemented in Zig, designed for developers and infrastructure use cases.

## 🎯 Overview

`sui-zig-rpc-client` is a developer-focused tool for interacting with the Sui blockchain. It provides a complete toolkit for:

- **Transaction Management**: Build, simulate, sign, and execute transactions
- **Wallet Operations**: Key management, address derivation, and asset queries
- **Smart Contract Interaction**: Deploy and call Move packages
- **Authentication**: WebAuthn/Passkey, hardware keys, and traditional signing
- **Developer Experience**: Natural language intent parsing, comprehensive CLI, and library APIs

## ✨ Features

### Core Capabilities
- ✅ **Full RPC Client** - Complete Sui JSON-RPC API support
- ✅ **Transaction Building** - Programmable Transaction Blocks (PTB) with BCS encoding
- ✅ **Multiple Signing Methods** - Ed25519, Secp256k1, Secp256r1
- ✅ **WebAuthn/Passkey** - Touch ID, Face ID, YubiKey support (macOS & Linux)
- ✅ **BIP-39 Mnemonics** - 12/24 word seed phrases with SLIP-0010 derivation
- ✅ **Intent Parser** - Natural language to transaction (swap, transfer, stake, etc.)
- ✅ **Caching System** - TTL-based caching with LRU eviction
- ✅ **WebSocket Support** - Real-time event subscriptions

### CLI Commands (50+)
- Wallet management (create, import, use, backup)
- Account queries (balance, coins, objects, resources)
- Transaction lifecycle (build, simulate, send, confirm, status)
- Move package operations (publish, upgrade, call)
- Event querying and monitoring
- Request lifecycle management

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/sui-zig-rpc-client.git
cd sui-zig-rpc-client

# Build the project
zig build

# Run tests
zig build test
```

### Basic Usage

```bash
# Get help
zig build run -- help

# Check version
zig build run -- version

# Query blockchain state
zig build run -- rpc sui_getLatestSuiSystemState

# Create a new wallet
zig build run -- wallet create --alias mywallet

# Check balance
zig build run -- wallet balance

# Build and send a transaction
zig build run -- tx build move-call \
  --package 0x2 \
  --module coin \
  --function transfer \
  --args '["0x1234", 1000]' \
  --gas-budget 1000000
```

## 📚 Documentation

### Core Documentation
- [Project Completion Summary](docs/PROJECT_COMPLETION_SUMMARY.md) - Comprehensive project overview
- [Architecture Overview](docs/COMMANDS_REFACTOR_SUMMARY.md) - Modular architecture details
- [Unimplemented Features](docs/UNIMPLEMENTED_FEATURES.md) - Future work and TODOs

### Feature Documentation
- [WebAuthn macOS Build](docs/WEBAUTHN_MACOS_BUILD.md) - Touch ID setup
- [ZKLogin Passkey](docs/ZKLOGIN_PASSKEY.md) - ZKLogin authentication
- [Touch ID Testing](docs/TOUCH_ID_TESTING.md) - Testing guide
- [Wallet Core v1](docs/wallet-core-v1-checklist.md) - Wallet features

### Development
- [Code Review Report](docs/CODE_REVIEW_REPORT_FINAL.md) - Code quality assessment
- [Deprecation Plan](docs/DEPRECATION_PLAN.md) - Migration guide
- [Test Matrix](docs/bootcamp-test-matrix.md) - Testing coverage

## 🏗️ Architecture

```
src/
├── cli/                    # CLI parsing and validation (8 modules)
├── client/rpc_client/      # RPC client implementation (17 modules)
├── commands/               # Command handlers (11 modules)
├── tx_request_builder/     # Transaction building (7 modules)
├── ptb_bytes_builder/      # PTB encoding (5 modules)
├── webauthn/               # WebAuthn/Passkey support
├── wallet/                 # Wallet management
├── plugin/                 # Plugin system
└── graphql/                # GraphQL client
```

## 🧪 Testing

### Run All Tests
```bash
# Zig unit tests
zig build test --summary all

# Move contract tests
zig build move-fixture-test

# Full test suite with release gate
bash scripts/wallet_core_v1_release_gate.sh
```

### Test Coverage
- **140+ unit tests** covering all major components
- **8 Move contract test suites** for local validation
- **Integration tests** for end-to-end workflows
- **Smoke tests** for mainnet validation

## 💡 Usage Examples

### Wallet Operations

```bash
# Create wallet with mnemonic
zig build run -- wallet create --alias main --json

# Import from private key
zig build run -- wallet import --private-key <key> --alias imported

# List all wallets
zig build run -- wallet accounts

# Check specific wallet balance
zig build run -- wallet balance main --coin-type 0x2::sui::SUI
```

### Transaction Examples

```bash
# Build a transfer transaction
zig build run -- tx build move-call \
  --package 0x2 \
  --module sui \
  --function transfer \
  --args '["0xrecipient", 1000000]' \
  --summarize

# Simulate before sending
zig build run -- tx simulate \
  --package 0x2 \
  --module coin \
  --function transfer \
  --sender 0xsender \
  --summarize

# Send with confirmation
zig build run -- tx send \
  --tx-bytes <bytes> \
  --signature <sig> \
  --observe
```

### Natural Language Intents

```bash
# Parse natural language to transaction
zig build run -- natural-do "swap 100 SUI for USDC"
zig build run -- natural-do "send 50 SUI to 0x1234"
zig build run -- natural-do "stake all my SUI"
zig build run -- natural-do "claim my rewards"
```

## 🔐 Authentication

### WebAuthn/Passkey
```bash
# Register a new passkey
zig build run -- wallet passkey register 0xaddress

# List registered passkeys
zig build run -- wallet passkey list

# Login with passkey
zig build run -- wallet passkey login <credential-id>
```

### Provider Session
```bash
# Use session-backed provider
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --provider @examples/provider/passkey.json \
  --session-response @examples/provider/response.json
```

## 📊 Project Statistics

| Metric | Value |
|--------|-------|
| **Files** | 106 Zig files |
| **Code** | ~33,000 lines |
| **Tests** | 140+ tests |
| **Docs** | 32 markdown files |
| **Modules** | 48 sub-modules |
| **Intents** | 6 intent types |

## 🛠️ Development

### Building
```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseFast

# With WebAuthn support (macOS)
zig build -Dwebauthn=true
```

### Project Structure
- `src/` - Source code
- `docs/` - Documentation
- `fixtures/` - Test fixtures and Move contracts
- `scripts/` - Utility scripts
- `examples/` - Example configurations

## 🤝 Contributing

Priority areas for contributions:
1. **Advanced Wallet Features** - Session management, policies
2. **GraphQL Integration** - Query builder, schema introspection
3. **Plugin System** - Dynamic loading, example plugins
4. **Documentation** - Tutorials, API docs

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Sui Foundation for the excellent blockchain platform
- Zig community for the amazing language and tooling
- Contributors who helped improve this project

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/sui-zig-rpc-client/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/sui-zig-rpc-client/discussions)
- **Documentation**: See `docs/` directory

---

**Status**: ✅ **Production Ready** | **Version**: 0.1.0 | **Last Updated**: 2026-03-22
