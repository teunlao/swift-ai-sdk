// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "SwiftAISDKExamples",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    // ExamplesCore - shared utilities
    .library(
      name: "ExamplesCore",
      targets: ["ExamplesCore"]
    ),
  ],
  dependencies: [
    // Local Swift AI SDK dependency
    .package(path: "../"),
  ],
  targets: [
    // MARK: - Core Utilities

    .target(
      name: "ExamplesCore",
      dependencies: [
        .product(name: "OpenAIProvider", package: "swift-ai-sdk")
      ]
    ),

    .executableTarget(
      name: "AICoreExamples",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKJSONSchema", package: "swift-ai-sdk"),
        .product(name: "AISDKZodAdapter", package: "swift-ai-sdk"),
        .product(name: "AnthropicProvider", package: "swift-ai-sdk"),
        .product(name: "DeepgramProvider", package: "swift-ai-sdk"),
        .product(name: "AssemblyAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - Getting Started Examples

    .executableTarget(
      name: "BasicGeneration",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "StreamingExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "ToolsExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKZodAdapter", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "StructuredOutputExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "BasicCLI",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - AI SDK Core Examples

    .executableTarget(
      name: "BasicTextGeneration",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "GenerateObjectExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "EmbeddingsExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "ImageGenerationExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "SpeechExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "TranscriptionExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "MiddlewareExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "ProviderManagementExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "ErrorHandlingExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProvider", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "TestingExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "AISDKProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "TelemetryExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - README Examples

    .executableTarget(
      name: "READMEExamples",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKJSONSchema", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - JSON Schema Examples

    .executableTarget(
      name: "JSONSchemaAutoExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKJSONSchema", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "ZodConstraintsTest",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKJSONSchema", package: "swift-ai-sdk"),
        .product(name: "AISDKZodAdapter", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - Zod Adapter Examples

    .executableTarget(
      name: "CalculatorExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKZodAdapter", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "DatabaseQueryExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKZodAdapter", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "EmailSenderExample",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
        .product(name: "AISDKZodAdapter", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - Debug/Test Examples

    .executableTarget(
      name: "TestSystemPrompt",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - Documentation Validation

    .executableTarget(
      name: "ProviderValidation-OpenAI",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "OpenAIProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
      ]
    ),

    .executableTarget(
      name: "ProviderValidation-Anthropic",
      dependencies: [
        "ExamplesCore",
        .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
        .product(name: "AnthropicProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProvider", package: "swift-ai-sdk"),
        .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
      ]
    ),

    // MARK: - Tests
    // TODO: Add test targets later
  ]
)
