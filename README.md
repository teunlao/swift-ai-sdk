# Swift AI SDK

> ⚠️ **WORK IN PROGRESS** ⚠️
>
> **This project is currently under active development and is NOT production-ready.**
>
> - ❌ **NOT functional yet** - Core functionality is still being implemented
> - ❌ **NOT stable** - APIs will change without notice
> - ❌ **NOT suitable for production use**
>
> This is an experimental port. Use at your own risk.

Unofficial Swift port of the Vercel AI SDK. The goal is to mirror the original TypeScript implementation 1:1 (API, behavior, tests), adapting it to Swift and SwiftPM conventions.

## Package Structure

This SDK is organized into **3 separate SwiftPM packages** matching upstream `@ai-sdk` architecture:

### 📦 AISDKProvider
**Foundation types and protocols** (no dependencies)
- LanguageModel V2/V3 protocols and types
- EmbeddingModel V2/V3, ImageModel V2/V3
- SpeechModel V2/V3, TranscriptionModel V2/V3
- Provider error types
- JSONValue universal JSON type
- Core middleware interfaces

**Import**: `import AISDKProvider`

### 🔧 AISDKProviderUtils
**Utility functions and helpers** (depends on AISDKProvider)
- HTTP client utilities (GET/POST, headers, retries)
- JSON parsing and validation
- Schema definitions and type validation
- Tool definitions and utilities
- SSE event stream parsing
- ID generation, delays, user-agent handling

**Import**: `import AISDKProviderUtils`

### 🚀 SwiftAISDK
**Main AI SDK** (depends on AISDKProvider + AISDKProviderUtils + EventSourceParser)
- `generateText()` / `streamText()` high-level functions
- Prompt conversion and standardization
- Tool execution and MCP integration
- Provider registry and model resolution
- Telemetry and logging
- Middleware (default settings, reasoning extraction, streaming simulation)

**Import**: `import SwiftAISDK`

### Project Files
- `Package.swift` – SwiftPM manifest with 3 library targets
- `Sources/AISDKProvider/` – Foundation package (78 files)
- `Sources/AISDKProviderUtils/` – Utilities package (35 files)
- `Sources/SwiftAISDK/` – Main SDK package (105 files)
- `Sources/EventSourceParser/` – SSE parser
- `Tests/` – Test suites for each package
- `external/` – Upstream Vercel AI SDK sources (ignored by Git) for reference
- `plan/` – Development documentation (ignored by Git)

## Status
**Active Development** - Core provider infrastructure is being implemented.

### Completed ✅
- **AISDKProvider Package** (78 files):
  - LanguageModelV2 (17 types) - 100% parity
  - LanguageModelV3 (17 types) - 100% parity
  - EmbeddingModel V2/V3, ImageModel V2/V3
  - SpeechModel V2/V3, TranscriptionModel V2/V3
  - Provider errors (26 error types)
  - JSONValue universal JSON type
  - Middleware protocols

- **AISDKProviderUtils Package** (35 files):
  - HTTP client utilities (GET/POST, headers, retries)
  - JSON parsing, schema validation, type validation
  - Tool definitions and utilities
  - ID generation, delays, user-agent handling
  - Data URL parsing, media type detection
  - SSE event stream parsing integration

- **SwiftAISDK Package** (105 files):
  - Prompt conversion and standardization
  - Tool execution framework
  - Provider registry and model resolution
  - Middleware (default settings, reasoning, streaming)
  - Core error types and response handling
  - Mock models for testing

- **EventSourceParser** (SSE parsing) - 100% parity with `eventsource-parser@3.0.6`

### Current Stats
- ✅ Build: `swift build` — ~2.3s (3 packages)
- ✅ Tests: 763/763 passed (100% pass rate)
  - EventSourceParser: 30 tests
  - AISDKProvider: ~210 tests
  - AISDKProviderUtils: ~200 tests
  - SwiftAISDK: ~300 tests
- 📊 Total: ~14,300 lines of code across 220 files

## Known Limitations & Parity Deviations

### Schema/Validation
- **Zod/ArkType/Effect/Valibot not ported**: JS-specific libraries have no Swift equivalents. Using vendor `"zod"` throws `UnsupportedStandardSchemaVendorError`.
- **Solution**: Use `Schema.codable()` for Decodable types or provide custom JSON Schema + validation closure.

### HTTP Response
- **statusText**: TypeScript uses server's HTTP reason phrase; Swift uses localized system string due to Foundation API limitation.
- **Impact**: Minimal - custom error messages are in response body, not status line.

### Error Structure
- **ValidateTypes**: Swift uses single-level TypeValidationError wrapping vs TypeScript's double-wrapping.
- **Impact**: Error introspection differs but functional behavior identical.

## Upstream Reference
- Vercel AI SDK 6.0.0-beta.42 (`77db222eeded7a936a8a268bf7795ff86c060c2f`).

## License
Swift AI SDK is an independent port of the Vercel AI SDK (Apache License 2.0).  
This repository is distributed under the **Apache License 2.0**—see [`LICENSE`](LICENSE) for the full text.  
Portions of the code are adapted from the upstream Vercel AI SDK project; all modifications are documented within this repo.
