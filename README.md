<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logos/logo-white.png" />
    <source media="(prefers-color-scheme: light)" srcset="logos/logo-black.png" />
    <img alt="Swift AI SDK" src="logos/logo-black.png" width="320" />
  </picture>
</p>

# Swift AI SDK

[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/teunlao/swift-ai-sdk)](https://github.com/teunlao/swift-ai-sdk/releases)
[![Documentation](https://img.shields.io/badge/docs-swift--ai--sdk-blue)](https://swift-ai-sdk-docs.vercel.app)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fteunlao%2Fswift-ai-sdk%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/teunlao/swift-ai-sdk)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fteunlao%2Fswift-ai-sdk%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/teunlao/swift-ai-sdk)

A unified AI SDK for Swift: streaming chat/completions, structured outputs, tool/function/MCP calling, and middleware — with 28+ providers via one API (OpenAI, Anthropic, Google, Groq, xAI). Based on the [Vercel AI SDK](https://github.com/vercel/ai) with a focus on full API parity.

**[Documentation](https://swift-ai-sdk-docs.vercel.app)** | **[Getting Started](https://swift-ai-sdk-docs.vercel.app/getting-started/ios-macos-quickstart)** | **[Examples](examples/)** | **[Discussions](https://github.com/teunlao/swift-ai-sdk/discussions)**

## Features

- Streaming and non-streaming text generation
- Structured outputs (typed `Codable` + JSON Schema)
- Tool/function calling + MCP tools
- Provider-agnostic API (swap providers without changing call sites)
- Middleware hooks

## Installation (SwiftPM)

Available on [Swift Package Index](https://swiftpackageindex.com/teunlao/swift-ai-sdk).

Add the package to your `Package.swift`:

```swift
// Package.swift
dependencies: [
  // Use the latest release tag (e.g. "0.8.5").
  .package(url: "https://github.com/teunlao/swift-ai-sdk.git", from: "0.8.5")
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

## Quickstart (Streaming)

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

More examples (tools, structured output, middleware) are in the docs and `examples/`.

## Unified Provider Architecture

Switch providers without changing code — the function signature stays the same regardless of provider.

```swift
import SwiftAISDK
import OpenAIProvider
import AnthropicProvider
import GoogleProvider

let models: [LanguageModel] = [
  openai("gpt-5"),
  anthropic("claude-4.5-sonnet"),
  google("gemini-2.5-pro")
]

for model in models {
  let result = try await generateText(
    model: model,
    prompt: "Invent a new holiday and describe its traditions."
  )
  print(result.text)
}
```

## Structured Outputs (Typed `Codable`)

Generate structured data validated by JSON Schema or `Codable`.

Example: extract a release summary into a `Release` type using `Schema.codable`.

```swift
import SwiftAISDK
import OpenAIProvider

struct Release: Codable, Sendable {
  let name: String
  let version: String
  let changes: [String]
}

let summary = try await generateObject(
  model: openai("gpt-5"),
  schema: Release.self,
  schemaName: "release_summary",
  prompt: "Summarize Swift AI SDK 0.1.0: streaming + tools."
).object

print("Release: \\(summary.name) (\\(summary.version))")
summary.changes.forEach { print("- \($0)") }
```

Notes: use `generateObjectNoSchema(...)` for raw `JSONValue`; arrays/enums via `generateObjectArray` / `generateObjectEnum`.

## Tools (Typed)

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
  inputSchema: WeatherQuery.self,
  execute: { (query, _) in
    WeatherReport(
      location: query.location,
      temperatureFahrenheit: Int.random(in: 62...82)
    )
  }
)

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

## Providers

- Provider overview: https://swift-ai-sdk-docs.vercel.app/providers/overview
- Each provider lives in its own SwiftPM product (e.g. `OpenAIProvider`, `AnthropicProvider`, `GoogleProvider`).

## Upstream & Parity

This project ports the Vercel AI SDK with a focus on behavior/API parity.

- Upstream reference (pinned commit): `upstream/UPSTREAM.md`

## Contributing

Contributions welcome. See CONTRIBUTING.md for guidelines.

## License

Apache 2.0. Portions adapted from the Vercel AI SDK under Apache 2.0.
