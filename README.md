# Swift AI SDK

Unified AI SDK for Swift — a 1:1 port of the Vercel AI SDK with the same API and behavior.

- SwiftPM package set: `SwiftAISDK`, `AISDKProvider`, `AISDKProviderUtils`, provider modules (`OpenAIProvider`, `AnthropicProvider`, `GoogleProvider`, `GroqProvider`, `OpenAICompatibleProvider`).
- Platforms: iOS 16+, macOS 13+, tvOS 16+, watchOS 9+. See `Package.swift` for source of truth.
- Upstream parity target: Vercel AI SDK 6.0.0-beta.42 (commit `77db222ee`).

## Installation (SwiftPM)

Add the package to your `Package.swift`:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/teunlao/swift-ai-sdk.git", branch: "main")
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

## UI Integration (JS‑only)

React/Next.js AI SDK UI is JS‑only and not part of this Swift package. See the upstream AI SDK UI docs if you build hybrid apps.

## Templates & Examples

See `examples/` in this repo and the docs site under `apps/docs`.

## Community & Support

Use GitHub Issues for bugs/ideas; report vulnerabilities privately (see Security).

## Authors / About

Inspired by the Vercel AI SDK. This independent port brings a unified, strongly‑typed AI SDK to the Swift ecosystem while preserving upstream behavior.
