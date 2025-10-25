# Swift AI SDK

[![Tests](https://github.com/teunlao/swift-ai-sdk/actions/workflows/test.yml/badge.svg)](https://github.com/teunlao/swift-ai-sdk/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/teunlao/swift-ai-sdk/graph/badge.svg?token=381f5745-12c8-4720-93c7-9748cbb96359)](https://codecov.io/gh/teunlao/swift-ai-sdk)
[![Swift Version](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/teunlao/swift-ai-sdk)](https://github.com/teunlao/swift-ai-sdk/releases)
[![Documentation](https://img.shields.io/badge/docs-swift--ai--sdk-blue)](https://swift-ai-sdk-docs.vercel.app)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fteunlao%2Fswift-ai-sdk%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/teunlao/swift-ai-sdk)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fteunlao%2Fswift-ai-sdk%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/teunlao/swift-ai-sdk)

A unified AI SDK for Swift, bringing the power of [Vercel AI SDK](https://github.com/vercel/ai) to Apple platforms with 100% API parity.

**[Documentation](https://swift-ai-sdk-docs.vercel.app)** | **[Getting Started](https://swift-ai-sdk-docs.vercel.app/getting-started/ios-macos-quickstart)** | **[Examples](examples/)** | **[Discussions](https://github.com/teunlao/swift-ai-sdk/discussions)**

## Features

- **Text Generation** - Streaming and non-streaming
- **Structured Outputs** - Type-safe object generation with schemas
- **Tool Calling** - Function calling and MCP tools
- **Multi-Provider** - OpenAI, Anthropic, Google, Groq, xAI, and [more](https://swift-ai-sdk-docs.vercel.app/providers/overview)
- **Middleware System** - Extensible request/response processing
- **Telemetry** - Built-in observability

## Packages

**Core SDK:**
- `SwiftAISDK` - Main SDK with text generation, streaming, tools
- `AISDKProvider` - Foundation types and interfaces
- `AISDKProviderUtils` - Provider utilities

**Providers:**
- OpenAI, Anthropic, Google, Groq, xAI, Azure, and [more](https://swift-ai-sdk-docs.vercel.app/providers/overview)

---

## Implementation Status

**Updated**: 2025-10-24
**Upstream:** Based on Vercel AI SDK 6.0.0-beta.42

| Category | Tests | Coverage |
|----------|-------|----------|
| **Core SDK** | 1547 | 100% |
| **Providers** | 883 | 62.7% |
| **Overall** | 2430 | 83% |

<details>
<summary>Provider Details</summary>

| Provider | Impl | Tests | Upstream | Swift | Coverage |
|----------|:----:|:-----:|----------|-------|----------|
| **openai** | ✅ | ✅ | 290 | 290 | 100% |
| **anthropic** | ✅ | ✅ | 114 | 114 | 100% |
| **google** | ✅ | ✅ | 155 | 155 | 100% |
| **groq** | ✅ | ✅ | 58 | 58 | 100% |
| **xai** | ✅ | ✅ | 50 | 50 | 100% |
| **azure** | ✅ | ✅ | 26 | 26 | 100% |
| **openai-compatible** | ✅ | ✅ | 128 | 128 | 100% |
| **cerebras** | ✅ | ✅ | 7 | 7 | 100% |
| **deepseek** | ✅ | ✅ | 13 | 13 | 100% |
| **baseten** | ✅ | ✅ | 25 | 25 | 100% |
| **replicate** | ✅ | ✅ | 11 | 11 | 100% |
| **lmnt** | ✅ | ✅ | 9 | 9 | 100% |
| **amazon-bedrock** | ❌ | ❌ | 152 | 0 | 0% |
| **google-vertex** | ❌ | ❌ | 78 | 0 | 0% |
| **cohere** | ❌ | ❌ | 48 | 0 | 0% |
| **mistral** | ❌ | ❌ | 44 | 0 | 0% |
| **huggingface** | ❌ | ❌ | 32 | 0 | 0% |
| **fal** | ❌ | ❌ | 26 | 0 | 0% |
| **fireworks** | ❌ | ❌ | 23 | 0 | 0% |
| **perplexity** | ❌ | ❌ | 19 | 0 | 0% |
| **deepinfra** | ❌ | ❌ | 18 | 0 | 0% |
| **togetherai** | ❌ | ❌ | 17 | 0 | 0% |
| **luma** | ❌ | ❌ | 16 | 0 | 0% |
| **elevenlabs** | ❌ | ❌ | 15 | 0 | 0% |
| **hume** | ❌ | ❌ | 9 | 0 | 0% |
| **assemblyai** | ❌ | ❌ | 6 | 0 | 0% |
| **deepgram** | ❌ | ❌ | 6 | 0 | 0% |
| **gladia** | ❌ | ❌ | 6 | 0 | 0% |
| **revai** | ❌ | ❌ | 6 | 0 | 0% |
| **vercel** | ❌ | ❌ | 4 | 0 | 0% |
| **TOTAL** | **12/32** | **12/32** | **1409** | **883** | **62.7%** |

</details>

---

## Installation (SwiftPM)

Available on [Swift Package Index](https://swiftpackageindex.com/teunlao/swift-ai-sdk).

Add the package to your `Package.swift`:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/teunlao/swift-ai-sdk.git", from: "0.1.6")
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

Switch providers without changing code.

```swift
import SwiftAISDK
import OpenAIProvider

// Use convenience function
let model = openai("gpt-5")

// Or configure explicitly
let provider = createOpenAIProvider(settings: .init(
  baseURL: ProcessInfo.processInfo.environment["OPENAI_BASE_URL"],
  apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
))
let model = provider("gpt-5")
```

## Platforms & Requirements

- Swift 6.1 toolchain (see `swift-tools-version` in `Package.swift`).
- iOS 16+, macOS 13+, tvOS 16+, watchOS 9+ (source of truth: `Package.swift`).

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

Models can call tools. Typed weather example:

```swift
import SwiftAISDK
import OpenAIProvider
import Foundation

struct WeatherQuery: Codable, Sendable {
  let location: String
}

struct WeatherReport: Codable, Sendable {
  let location: String
  let temperatureFahrenheit: Int
}

let weatherTool = tool(
  description: "Get the weather in a location",
  inputSchema: WeatherQuery.self
) { (query: WeatherQuery, _) in
  WeatherReport(
    location: query.location,
    temperatureFahrenheit: Int.random(in: 62...82)
  )
}

let result = try await generateText(
  model: openai("gpt-4.1"),
  tools: ["weather": weatherTool.tool],
  prompt: "Use the weather tool to fetch the weather for San Francisco."
)

if let toolResult = result.toolResults.first {
  let report = try weatherTool.decodeOutput(from: toolResult)
  print(report)
}
```

Notes: `tool(...)` auto-generates schemas from `Codable` types. For streaming, use `streamText(..., tools: ...)` and consume `textStream`/`toolResults`.

## Templates & Examples

See `examples/` in this repo and the docs site under `apps/docs`.

## Upstream & Parity

Based on Vercel AI SDK 6.0.0-beta.42 (commit `77db222ee`).

### Compatibility
- Swift 6.1, iOS 16+, macOS 13+, tvOS 16+, watchOS 9+
- JS schema vendors (zod/arktype/valibot) not supported; use `Schema.codable` or JSON Schema

## Contributing

Contributions welcome. See CONTRIBUTING.md for guidelines.

## License

Apache 2.0. Portions adapted from the Vercel AI SDK under Apache 2.0.
