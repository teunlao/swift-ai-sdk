# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2025-10-21

### Changed
- Lower swift-tools-version from 6.1 to 6.0 for broader compatibility

## [0.1.0] - 2025-10-20

### Added

**Core SDK** (3/3 packages - 101.8% test coverage):
- `AISDKProvider` - Foundation types (139 tests)
- `AISDKProviderUtils` - Provider utilities (272 tests, 85.0% coverage)
- `SwiftAISDK` - Main SDK (1136 tests, 94.7% coverage)

**Providers** (5/32 ported):
- `OpenAIProvider` - Complete (292 tests, 100.7% coverage)
- `AnthropicProvider` - Complete (115 tests, 100.9% coverage)
- `GoogleProvider` - Partial (20 tests, 12.9% coverage)
- `GroqProvider` - Partial (19 tests, 32.8% coverage)
- `OpenAICompatibleProvider` - Partial (9 tests, 7.0% coverage)

**Features**:
- Text generation: `generateText()`, `streamText()`
- Structured output: `generateObject()`, `streamObject()`
- Tool calling and MCP tools support
- Middleware system for language models
- Telemetry and error handling
- Zod-like schema DSL (`AISDKZodAdapter`)
- SSE streaming parser (`EventSourceParser`)

**Platform Support**:
- iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

**Test Coverage**:
- Total: 1728 tests passing
- Upstream parity: 68.4% (2002/2928 relevant upstream tests)

**Upstream Reference**:
- Vercel AI SDK 6.0.0-beta.42 (commit 77db222eeded7a936a8a268bf7795ff86c060c2f)
