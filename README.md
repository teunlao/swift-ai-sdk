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
- **JSONValue** - Universal JSON type with Codable support

### Current Stats
- ✅ Build: `swift build` — ~1.2s
- ✅ Tests: 92/92 passed (EventSourceParser: 30, V2 types: 36, Provider Errors: 26)
- 📊 Total: ~4000+ lines of code across 60+ files

## Upstream Reference
- Vercel AI SDK 6.0.0-beta.42 (`77db222eeded7a936a8a268bf7795ff86c060c2f`).
