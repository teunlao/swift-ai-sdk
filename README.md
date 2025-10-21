# Swift AI SDK

[![Tests](https://github.com/teunlao/swift-ai-sdk/actions/workflows/test.yml/badge.svg)](https://github.com/teunlao/swift-ai-sdk/actions/workflows/test.yml)
[![Swift Version](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/teunlao/swift-ai-sdk)](https://github.com/teunlao/swift-ai-sdk/releases)
[![Documentation](https://img.shields.io/badge/docs-swift--ai--sdk-blue)](https://swift-ai-sdk-docs.vercel.app)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fteunlao%2Fswift-ai-sdk%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/teunlao/swift-ai-sdk)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fteunlao%2Fswift-ai-sdk%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/teunlao/swift-ai-sdk)

A unified AI SDK for Swift, bringing the power of [Vercel AI SDK](https://github.com/vercel/ai) to Apple platforms with 100% API parity.

📖 **[Documentation](https://swift-ai-sdk-docs.vercel.app)** | 🚀 **[Getting Started](https://swift-ai-sdk-docs.vercel.app/getting-started/ios-macos-quickstart)** | 💬 **[Discussions](https://github.com/teunlao/swift-ai-sdk/discussions)**

## ✨ Features

- **Text Generation** - Streaming and non-streaming text generation
- **Structured Outputs** - Type-safe object generation with schemas
- **Tool Calling** - Function calling and MCP tools support
- **Multi-Provider** - OpenAI, Anthropic, Google, Groq, and more
- **Middleware System** - Extensible request/response processing
- **Telemetry** - Built-in observability and monitoring
- **Cross-Platform** - iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

## 📦 Packages

**Core SDK:**
- `SwiftAISDK` - Main AI SDK with text generation, streaming, tools
- `AISDKProvider` - Foundation types and interfaces
- `AISDKProviderUtils` - Provider utilities and helpers

**Providers:**
- `OpenAIProvider` - OpenAI (GPT-4, GPT-3.5, etc.)
- `AnthropicProvider` - Anthropic Claude
- `GoogleProvider` - Google Gemini
- `GroqProvider` - Groq
- `OpenAICompatibleProvider` - OpenAI-compatible APIs

**Upstream:** Based on Vercel AI SDK 6.0.0-beta.42 (commit `77db222ee`)

---

## 📊 Implementation Status

**Updated**: 2025-10-20

### 🎯 Overall

| Metric | Upstream | Swift | Coverage |
|--------|----------|-------|----------|
| **Packages** | 35* | 11 | 31.4% |
| **Tests** | 2928** | 2002 | 68.4% |

_* Excludes 7 frontend frameworks (React, Angular, etc.) and 4 infrastructure packages (codemod, rsc, etc.) not applicable to Swift_
_** Core SDK (1519) + Providers (1409), excludes frameworks/infrastructure_

### 📦 Core SDK (3/3 packages)

| Package | Upstream | Swift | Coverage | Status |
|---------|----------|-------|----------|:------:|
| **provider** | 0 | 139 | ∞% | ✅ |
| **provider-utils** | 320 | 272 | 85.0% | ⚠️ |
| **ai** | 1199 | 1136 | 94.7% | ✅ |
| **TOTAL** | **1519** | **1547** | **101.8%** | **✅** |

### 🔌 Providers (5/32 ported)

**Test counts** (Upstream = TypeScript tests | Swift = Swift tests ported)

| Provider | Impl | Tests | Upstream | Swift | Coverage |
|----------|:----:|:-----:|----------|-------|----------|
| **openai** | ✅ | ✅ | 290 | 292 | 100.7% |
| **anthropic** | ✅ | ✅ | 114 | 115 | 100.9% |
| **google** | ✅ | 🔴 | 155 | 20 | 12.9% |
| **groq** | ✅ | 🔴 | 58 | 19 | 32.8% |
| **openai-compatible** | ✅ | ⚠️ | 128 | 9 | 7.0% |
| **amazon-bedrock** | ❌ | ❌ | 152 | 0 | 0% |
| **google-vertex** | ❌ | ❌ | 78 | 0 | 0% |
| **xai** | ❌ | ❌ | 50 | 0 | 0% |
| **cohere** | ❌ | ❌ | 48 | 0 | 0% |
| **mistral** | ❌ | ❌ | 44 | 0 | 0% |
| **huggingface** | ❌ | ❌ | 32 | 0 | 0% |
| **fal** | ❌ | ❌ | 26 | 0 | 0% |
| **azure** | ❌ | ❌ | 26 | 0 | 0% |
| **baseten** | ❌ | ❌ | 25 | 0 | 0% |
| **fireworks** | ❌ | ❌ | 23 | 0 | 0% |
| **perplexity** | ❌ | ❌ | 19 | 0 | 0% |
| **deepinfra** | ❌ | ❌ | 18 | 0 | 0% |
| **togetherai** | ❌ | ❌ | 17 | 0 | 0% |
| **luma** | ❌ | ❌ | 16 | 0 | 0% |
| **elevenlabs** | ❌ | ❌ | 15 | 0 | 0% |
| **deepseek** | ❌ | ❌ | 13 | 0 | 0% |
| **replicate** | ❌ | ❌ | 11 | 0 | 0% |
| **lmnt** | ❌ | ❌ | 9 | 0 | 0% |
| **hume** | ❌ | ❌ | 9 | 0 | 0% |
| **cerebras** | ❌ | ❌ | 7 | 0 | 0% |
| **assemblyai** | ❌ | ❌ | 6 | 0 | 0% |
| **deepgram** | ❌ | ❌ | 6 | 0 | 0% |
| **gladia** | ❌ | ❌ | 6 | 0 | 0% |
| **revai** | ❌ | ❌ | 6 | 0 | 0% |
| **vercel** | ❌ | ❌ | 4 | 0 | 0% |
| **TOTAL** | **5/32** | **2/32** | **1409** | **455** | **32.3%** |

<details>
<summary>📊 Complete Summary & Progress Bars</summary>

### Summary

| Category | Packages | Upstream | Swift | Coverage | Status |
|----------|:--------:|----------|-------|----------|:------:|
| **Core SDK** | 3/3 | 1519 | 1547 | 101.8% | ✅ |
| **Providers** | 5/32 | 1409 | 455 | 32.3% | 🔴 |
| **Swift-specific** | 4 | - | 37 | - | 🎯 |
| **Frameworks** | 0/7 | 93 | 0 | N/A | ⏳ |
| **Infrastructure** | 0/4 | 300 | 0 | N/A | ⏳ |
| **TOTAL (all)** | **12/46** | **3323** | **2002** | **60.3%** | **⚠️** |
| **TOTAL (relevant)** | **11/35** | **2928** | **2002** | **68.4%** | **⚠️** |

### Progress Bars

**Core SDK**:
```
provider:       ████████████████████████████████  ∞%     (139/0)
provider-utils: ███████████████████████████░░░░░  85.0%  (272/320)
ai:             ██████████████████████████████░░  94.7%  (1136/1199)
────────────────────────────────────────────────────────
TOTAL:          ██████████████████████████████░░  101.8% (1547/1519)
```

**Providers (Ported)**:
```
openai:     ████████████████████████████████  100.7% (292/290)
anthropic:  ████████████████████████████████  100.9% (115/114)
google:     ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░  12.9%  (20/155)
groq:       ██████████░░░░░░░░░░░░░░░░░░░░░░  32.8%  (19/58)
────────────────────────────────────────────────
TOTAL:      ███████████░░░░░░░░░░░░░░░░░░░░░  31.6%  (446/1409)
```

**Overall**:
```
Core SDK:         ██████████████████████████████░░  101.8% (1547/1519)
Providers:        ██████████░░░░░░░░░░░░░░░░░░░░░  31.6%  (446/1409)
Frameworks:       ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0%     (0/93)
Infrastructure:   ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0%     (0/300)
───────────────────────────────────────────────────────────
TOTAL:            ███████████████████░░░░░░░░░░░░  60.0%  (1993/3323)
```

</details>

**Legend**:
- **Impl**: ✅ Implementation exists | ❌ Not implemented
- **Tests**: ✅ Complete (≥95%) | ⚠️ Partial (7-94%) | 🔴 Incomplete (<7%) | ❌ Not ported

**Note**: Test coverage indicates functional completeness vs upstream TypeScript implementation (Vercel AI SDK v6.0.0-beta.42).

---

## Installation (SwiftPM)

Available on [Swift Package Index](https://swiftpackageindex.com/teunlao/swift-ai-sdk).

Add the package to your `Package.swift`:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/teunlao/swift-ai-sdk.git", from: "0.1.0")
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
      .product(name: "OpenAIProvider", package: "swift-ai-sdk")
    ]
  )
]
```

## Quickstart

Minimal text generation and streaming with OpenAI:

```swift
import SwiftAISDK
import OpenAIProvider

@main
struct Demo {
  static func main() async throws {
    // Set OPENAI_API_KEY in your environment (loaded lazily by the provider).

    // Streaming text
    let stream = try streamText(
      model: openai("gpt-5"),
      prompt: "Stream one sentence about structured outputs."
    )
    for try await delta in stream.textStream {
      print(delta, terminator: "")
    }
  }
}
```

More examples (tools, structured output, telemetry, middleware) are available in the documentation.

## Unified Provider Architecture

Write once, swap providers without changing your app logic — same idea as the upstream AI SDK.

- Add only the provider modules you need via SwiftPM products (`OpenAIProvider`, `AnthropicProvider`, `GoogleProvider`, `GroqProvider`, `OpenAICompatibleProvider`).
- Use the convenience facade `openai("model-id")` or build a provider with settings via `createOpenAIProvider(settings:)`.

Minimal provider setup and call:

```swift
import SwiftAISDK
import OpenAIProvider

let provider = createOpenAIProvider(settings: .init(
  baseURL: ProcessInfo.processInfo.environment["OPENAI_BASE_URL"],
  apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
))

let model = provider("gpt-5") // alias of languageModel(modelId:)
let result = try await generateText(model: .v3(model), prompt: "Ping")
print(result.text)
```

## Features

- Unified provider architecture with consistent APIs across vendors.
- Text generation (`generateText`) and streaming (`streamText`) with SSE.
- Tool calls (static and dynamic), retries, stop conditions, usage accounting.
- Structured output with schemas, JSON mode, and partial output streams.
- Middleware and telemetry hooks mirroring upstream behavior.

## Platforms & Requirements

- Swift 6.1 toolchain (see `swift-tools-version` in `Package.swift`).
- iOS 16+, macOS 13+, tvOS 16+, watchOS 9+ (source of truth: `Package.swift`).

## Upstream & Parity

- Source of truth: Vercel AI SDK 6.0.0-beta.42 (commit `77db222ee`).
- Goal: identical public API, behaviors, and error messages; any intentional deviations are documented in `plan/design-decisions.md`.

### Compatibility Notes
- Swift 6.1, iOS 16+/macOS 13+; see `Package.swift` for authoritative constraints.
- Error messages mirror upstream text where applicable.
- HTTP `statusText` may differ due to Foundation APIs; see docs.
- JS‑only schema vendors (zod/arktype/effect/valibot) are not bundled; use `Schema.codable` or JSON Schema.
- Streaming uses URLSession + SSE; cancellation propagates via `AbortSignal` equivalent.
- Telemetry spans mirror upstream operation names (e.g., `ai.generateText`).
- Gateway usage is supported by pointing `baseURL` to your proxy.

## Security & Responsible Use

- Keep provider API keys in environment/Keychain; avoid logging secrets.
- Follow each provider’s Terms and data-handling policies.

## Contributing

Contributions are welcome. See CONTRIBUTING.md for guidelines (issues, PR workflow, code style, tests). Do not edit `external/` — it mirrors upstream and is read‑only.

## License & Trademarks

Licensed under Apache 2.0 (see `LICENSE`). This project is independent and not affiliated with Vercel or any model provider. “Vercel”, “OpenAI”, and other names are trademarks of their respective owners. Portions of the code are adapted from the Vercel AI SDK under Apache 2.0.

## Usage: Structured Data (generateObject)

Generate structured data validated by JSON Schema or `Codable`.

Example: extract a release summary into a `Release` type using `Schema.codable`.

```swift
import SwiftAISDK, OpenAIProvider, AISDKProviderUtils

struct Release: Codable, Sendable { let name, version: String; let changes: [String] }

let schema: Schema<Release> = .codable(
  Release.self,
  jsonSchema: .object([
    "type": .string("object"),
    "properties": .object([
      "name": .object(["type": .string("string")]),
      "version": .object(["type": .string("string")]),
      "changes": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
    ]),
    "required": .array([.string("name"), .string("version"), .string("changes")])
  ])
)

let result = try await generateObject(
  model: openai("gpt-5"),
  schema: .init(schema),
  prompt: "Summarize Swift AI SDK 0.1.0: streaming + tools."
)
print(result.object)
```

Notes: use `generateObjectNoSchema(...)` for raw `JSONValue`; arrays/enums via `generateObjectArray` / `generateObjectEnum`.

## Usage: Agents & Tools

Models can call tools. Minimal calculator example:

```swift
import SwiftAISDK, OpenAIProvider, AISDKProviderUtils

let calculate = tool(
  description: "Basic math",
  inputSchema: .jsonSchema(
    .object([
      "type": .string("object"),
      "properties": .object([
        "op": .object(["type": .string("string"), "enum": .array([.string("add"), .string("mul")])]),
        "a": .object(["type": .string("number")]),
        "b": .object(["type": .string("number")])
      ]),
      "required": .array([.string("op"), .string("a"), .string("b")])
    ])
  )
) { input, _ in
  guard case .object(let o) = input,
        case .string(let op) = o["op"],
        case .number(let a) = o["a"],
        case .number(let b) = o["b"] else {
    return .value(["error": .string("invalid input")])
  }
  let res = (op == "add") ? (a + b) : (a * b)
  return .value(["result": .number(res)])
}

let result = try await generateText(
  model: openai("gpt-5"),
  tools: ["calculate": calculate],
  prompt: "Use tools to compute 25*4."
)
print(result.text)
```

Notes: supports static and dynamic tool calls; for streaming with tools, use `streamText(..., tools: ...)` and consume `fullStream`.

## Templates & Examples

See `examples/` in this repo and the docs site under `apps/docs`.

## Community & Support

Use GitHub Issues for bugs/ideas

## Authors / About

Inspired by the Vercel AI SDK. This independent port brings a unified, strongly‑typed AI SDK to the Swift ecosystem while preserving upstream behavior.
