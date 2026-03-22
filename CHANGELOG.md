# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-23

### Added
- Complete Sui RPC client implementation with Zig
- WebAuthn/Passkey support for macOS (Touch ID) and Linux (libfido2)
- BIP-39 mnemonic generation (12/24 words) with SLIP-0010 derivation
- Transaction building, simulation, signing, and execution
- 50+ CLI commands covering wallet, account, transaction operations
- WebSocket subscriptions for real-time events
- Caching system with TTL and LRU eviction
- Intent parser supporting 6 types (swap, transfer, balance, stake, unstake, claim)
- GraphQL client framework
- Plugin system architecture
- Comprehensive test suite (550+ tests, 8 Move contract suites)
- CI/CD with GitHub Actions
- Makefile for common tasks
- 15 core documentation files

### Changed
- Migrated from monolithic to modular architecture (48 sub-modules)
- Restructured documentation with archive for historical plans
- Documented all NotImplemented placeholders with context

### Removed
- 17 obsolete files (test files, demo files, build artifacts)
- 21 outdated planning documents (moved to archive)

## [0.1.1.0] - 2026-03-21

### Added
- Natural language command `sui do` for intuitive blockchain interactions
- Support for swap intents: `sui do "swap 100 SUI for USDC"`
- Smart token order detection based on natural language phrasing
- Support for "all" keyword to swap entire balance
- Structured intent JSON parsing via `--intent-json` flag
- Local intent parsing without external API dependencies
- Extensible intent parser architecture for future intent types

### Changed
- Refactored command dispatch to support natural language commands
- Enhanced CLI argument parsing for multi-word natural language queries
