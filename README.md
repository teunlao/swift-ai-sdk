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

## Structure
- `Package.swift` – SwiftPM manifest.
- `Sources/SwiftAISDK` – library target placeholder.
- `Tests/SwiftAISDKTests` – initial test target.
- `external/` – checked-out Vercel AI SDK sources (ignored by Git) for reference during the port.
- `plan/` – локальные документы (игнорируются Git), описывающие стратегию и прогресс порта.

## Status
**Active Development** - Core provider infrastructure is being implemented.

### Completed ✅
- **EventSourceParser** (SSE parsing) - 100% parity with `eventsource-parser@3.0.6`
- **LanguageModelV2** (17 types) - 100% parity with upstream TypeScript
- **LanguageModelV3** (17 types) - 100% parity with upstream TypeScript
- **Provider Errors** (15 error types) - 100% parity with upstream TypeScript
- **ProviderUtils** (15 utilities) - ID generation, Delay, Headers, UserAgent, LoadSettings, HTTP Utils, Version, SecureJsonParse
- **JSONValue** - Universal JSON type with Codable support

### Current Stats
- ✅ Build: `swift build` — ~0.7-0.9s
- ✅ Tests: 236/236 passed (EventSourceParser: 30, V2: 50, V3: 39, Errors: 26, ProviderUtils: 77, JSONValue)
- 📊 Total: ~9500+ lines of code across 104 files

## Known Limitations
- Schema helpers (`Schema`, `parseJSON`, `validateTypes`) accept Swift-native validators or JSON Schema resolvers. Adapters for JS-centric libraries (`zod`, `arktype`, `effect`, `valibot`) are not ported; using vendor `"zod"` will throw `UnsupportedStandardSchemaVendorError`. Provide JSON Schema + validation closure (e.g., via `Schema.codable`) until a Swift DSL lands.

## Upstream Reference
- Vercel AI SDK 6.0.0-beta.42 (`77db222eeded7a936a8a268bf7795ff86c060c2f`).
