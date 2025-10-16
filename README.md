# Swift AI SDK

> ⚠️ **WORK IN PROGRESS** ⚠️
>
> **This project is currently under active development and is NOT production-ready.**

<!-- Branch isolation check: temporary comment for Task 10.1 experiment -->
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
- `Sources/AISDKProvider/` – Foundation package (79 files, 7,131 lines)
- `Sources/AISDKProviderUtils/` – Utilities package (36 files, 3,936 lines)
- `Sources/SwiftAISDK/` – Main SDK package (125 files, 14,834 lines)
- `Sources/EventSourceParser/` – SSE parser (3 files, 299 lines)
- `Tests/` – Test suites for each package (85 files, 21,655 lines)
- `external/` – Upstream Vercel AI SDK sources (ignored by Git) for reference
- `plan/` – Development documentation (ignored by Git)

## Playground CLI

The repository now contains an executable target `SwiftAISDKPlayground` that provides a lightweight CLI for manual smoke-tests against real providers.

### Build & Run

```bash
swift build
swift run playground chat --model gpt-4o-mini --prompt "Hello" --stream
```

Command options:

- `-P, --provider` – provider alias (`gateway` by default)
- `--model` – model identifier (required)
- `--prompt` / `--input-file` / `--stdin` – prompt sources
- `--stream` – stream deltas to stdout (macOS 12+)
- `--json-output` – emit final result as JSON
- `--verbose` / `--env-file` – global flags available before the subcommand

### Configuration

Credentials are read from environment variables and `.env` (see `.env.sample`). For gateway-based flows set:

```env
VERCEL_AI_API_KEY=your_token_here
# optional overrides
AI_GATEWAY_BASE_URL=https://ai-gateway.vercel.sh/v1/ai
```

If a required key is missing, the CLI reports a descriptive error. Streaming uses Server-Sent Events via `URLSession` + `EventSourceParser` and is available on macOS 12 or newer.

## Status
**Active Development** - Core provider infrastructure is being implemented.

### Completed ✅
- **AISDKProvider Package** (79 files, 7,131 lines):
  - LanguageModelV2 (17 types) - 100% parity
  - LanguageModelV3 (17 types) - 100% parity
  - EmbeddingModel V2/V3, ImageModel V2/V3
  - SpeechModel V2/V3, TranscriptionModel V2/V3
  - Provider errors (26 error types)
  - JSONValue universal JSON type
  - Middleware protocols

- **AISDKProviderUtils Package** (36 files, 3,936 lines):
  - HTTP client utilities (GET/POST, headers, retries)
  - JSON parsing, schema validation, type validation
  - Tool definitions and utilities
  - ID generation, delays, user-agent handling
  - Data URL parsing, media type detection
  - SSE event stream parsing integration

- **SwiftAISDK Package** (125 files, 14,834 lines):
  - Prompt conversion and standardization
  - Tool execution framework
  - Provider registry and model resolution
  - Middleware (default settings, reasoning, streaming)
  - Core error types and response handling
  - Mock models for testing
  - `generateText()` complete implementation (1,218 lines)

- **EventSourceParser** (3 files, 299 lines) - 100% parity with `eventsource-parser@3.0.6`

### Current Stats
- ✅ Build: `swift build` — ~2.3s (3 packages)
- ✅ Tests: **905/907 passed (99.8% pass rate)**
  - 907 individual test cases across all packages
  - 2 known failures in SerialJobExecutor (concurrent execution tests)
  - EventSourceParser: 30 tests
  - AISDKProvider: ~210 tests
  - AISDKProviderUtils: ~200 tests
  - SwiftAISDK: ~467 tests
- 📊 **Total: 26,200 lines of code across 243 files**
- 🧪 **Test coverage: 21,655 lines of test code across 85 test files**

## Swift vs TypeScript Comparison

Comparison with upstream **Vercel AI SDK 6.0.0-beta.42**:

| Metric | TypeScript (Upstream) | Swift (Port) | Difference |
|--------|----------------------|--------------|------------|
| **Source Files** | 445 files | 243 files | -45% |
| **Source Lines** | 31,581 lines | 26,200 lines | -17% |
| **Test Files** | 109 files | 85 files | -22% |
| **Test Lines** | 59,241 lines | 21,655 lines | -63% |
| **Test Count** | N/A | 907 tests | - |
| **Test Pass Rate** | N/A | 99.8% (905/907) | - |

### By Package

| Package | TypeScript | Swift | Difference |
|---------|-----------|-------|------------|
| **Provider** | 114 files, 4,298 lines | 79 files, 7,131 lines | +66% lines |
| **ProviderUtils** | 100 files, 4,824 lines | 36 files, 3,936 lines | -18% lines |
| **AI/SwiftAISDK** | 226 files, 21,995 lines | 125 files, 14,834 lines | -33% lines |
| **EventSourceParser** | 5 files, 464 lines | 3 files, 299 lines | -36% lines |

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
