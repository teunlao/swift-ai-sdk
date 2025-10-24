# Swift AI SDK Examples

Comprehensive, validated examples for the Swift AI SDK. Each example is self-contained, tested, and maps directly to documentation.

## 📁 Structure

```
examples/
├── Sources/
│   ├── ExamplesCore/          # Shared utilities (env loading, logging, helpers)
│   ├── GettingStarted/        # Quickstart examples from docs
│   ├── Agents/                # Agent examples and workflow patterns
│   ├── AISDKCore/             # Core API examples (text, objects, tools, etc.)
│   └── Foundations/           # Foundational concepts (prompts, tools, streaming)
├── Tests/                     # Validation that examples work
├── Scripts/                   # Helper scripts to run examples
└── Package.swift              # SwiftPM manifest
```

## 🚀 Quick Start

### 1. Setup Environment

Copy `.env.example` to `.env` and add your API keys:

```bash
cp .env.example .env
# Edit .env with your keys
```

Required environment variables:
```bash
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...
GROQ_API_KEY=gsk_...
```

### 2. Run Examples

**Run a specific example:**
```bash
./Scripts/run-example.sh GettingStarted/iOS-macOS/BasicGeneration
```

**Run all examples in a category:**
```bash
./Scripts/run-example.sh GettingStarted
./Scripts/run-example.sh AISDKCore/GeneratingText
```

**Run all examples:**
```bash
./Scripts/run-all.sh
```

**Validate examples match docs:**
```bash
./Scripts/validate-docs.sh
```

### 3. Build & Test

```bash
# Build all examples
swift build

# Run validation tests
swift test
```

## 📚 Examples Index

### Getting Started
- **iOS-macOS/**
  - `BasicGeneration.swift` - Simple text generation
  - `StreamingExample.swift` - Streaming in SwiftUI
  - `ToolsExample.swift` - Using tools with generateText

- **Server-Vapor/**
  - `SSEStreamingExample.swift` - Server-sent events streaming

- **CLI/**
  - `BasicCLI.swift` - Command-line tool example

### Agents
- `AgentBasics.swift` - Creating and using agents
- **WorkflowPatterns/**
  - `SequentialProcessing.swift` - Sequential workflow pattern
  - `ParallelProcessing.swift` - Parallel execution
  - `Routing.swift` - Dynamic routing pattern
  - `OrchestratorWorker.swift` - Orchestrator-worker pattern
  - `EvaluatorOptimizer.swift` - Evaluation and optimization
- `LoopControl.swift` - stopWhen and prepareStep

### AI SDK Core
- **GeneratingText/**
  - `BasicGeneration.swift` - generateText basics
  - `Streaming.swift` - streamText with callbacks
  - `Callbacks.swift` - onFinish, onChunk, onError

- **StructuredData/**
  - `GenerateObject.swift` - Schema-based object generation
  - `StreamObject.swift` - Streaming structured data
  - `OutputStrategies.swift` - array, enum, no-schema

- **JSONSchema/**
  - `JSONSchemaAutoExample.swift` - Automatic schema generation with .auto() for generateObject, streamObject, and tools

- **Tools/**
  - `BasicTools.swift` - Defining and using tools
  - `MultiStep.swift` - Multi-step tool execution
  - `DynamicTools.swift` - Runtime-defined tools
  - `MCPTools.swift` - Model Context Protocol integration

- **Embeddings/**
  - `BasicEmbedding.swift` - Single value embedding
  - `BatchEmbedding.swift` - embedMany for multiple values
  - `Similarity.swift` - Cosine similarity calculations

- **Images/**
  - `GenerateImage.swift` - Image generation examples

- **Transcription/**
  - `TranscribeAudio.swift` - Audio transcription

### Foundations
- **Prompts/**
  - `TextPrompts.swift` - Simple text prompts
  - `SystemPrompts.swift` - System prompt patterns
  - `MessagePrompts.swift` - Multi-turn conversations

- **Tools/**
  - `CustomTools.swift` - Creating custom tools

## 🧪 Testing

Examples include comprehensive tests to ensure:
- ✅ All examples compile and run
- ✅ Examples match documentation
- ✅ Examples produce expected outputs
- ✅ No regressions when SDK updates

Run tests:
```bash
swift test
```

## 📝 Adding New Examples

### 1. Create Example File

Place in appropriate category under `Sources/`:

```swift
import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct MyExample {
  static func main() async throws {
    // Load environment
    try EnvLoader.load()

    // Your example code
    let result = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Hello!"
    )

    Logger.success("Generated: \(result.text)")
  }
}
```

### 2. Add to Package.swift

```swift
.executableTarget(
  name: "MyExample",
  dependencies: ["SwiftAISDK", "OpenAIProvider", "ExamplesCore"]
)
```

### 3. Document in README

Add entry to examples index above.

### 4. Add Test

Create test in `Tests/ExamplesValidation/`:

```swift
import XCTest

final class MyExampleTests: XCTestCase {
  func testMyExample() async throws {
    // Validate example works
  }
}
```

## 🔍 Validation

### Docs Sync Validation

The `DocsSyncTests` validate that code examples in documentation actually work:

```bash
swift test --filter DocsSyncTests
```

This extracts Swift code blocks from `.mdx` files and validates they compile and run correctly.

### Manual Validation

```bash
# Validate specific example
./Scripts/run-example.sh AISDKCore/GeneratingText/BasicGeneration

# Validate all examples in category
./Scripts/run-example.sh AISDKCore
```

## 🛠 Development

### ExamplesCore Utilities

The `ExamplesCore` module provides:

- **EnvLoader** - `.env` file loading
- **Logger** - Consistent logging across examples
- **ExampleRunner** - Common example execution patterns
- **Helpers** - Shared utilities

Import in your examples:
```swift
import ExamplesCore
```

### Environment Variables

All examples use `EnvLoader.load()` to read `.env`:

```swift
try EnvLoader.load() // Loads from examples/.env
```

### Best Practices

1. **Keep examples focused** - One concept per file (50-200 lines)
2. **Match documentation** - Examples should mirror docs exactly
3. **Add comments** - Explain what's happening
4. **Handle errors** - Show proper error handling
5. **Use ExamplesCore** - Leverage shared utilities
6. **Test thoroughly** - Add validation tests

## 📊 CI/CD

GitHub Actions automatically:
- ✅ Builds all examples
- ✅ Runs validation tests
- ✅ Validates docs sync
- ✅ Reports failures

See `.github/workflows/examples.yml`

## 🔗 Links

- [Swift AI SDK Documentation](../apps/docs/)
- [Main SDK](../Sources/SwiftAISDK/)
- [Contributing Guide](../CONTRIBUTING.md)

## 📄 License

Same as Swift AI SDK (see root LICENSE)
