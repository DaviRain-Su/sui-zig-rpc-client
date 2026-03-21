# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
