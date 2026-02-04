// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAISDK",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16)
    ],
    products: [
        // Main products matching upstream @ai-sdk architecture
        .library(name: "AISDKProvider", targets: ["AISDKProvider"]),
        .library(name: "AISDKProviderUtils", targets: ["AISDKProviderUtils"]),
        .library(name: "SwiftAISDK", targets: ["SwiftAISDK"]),
        .library(name: "OpenAIProvider", targets: ["OpenAIProvider"]),
        .library(name: "OpenAICompatibleProvider", targets: ["OpenAICompatibleProvider"]),
        .library(name: "AnthropicProvider", targets: ["AnthropicProvider"]),
        .library(name: "AmazonBedrockProvider", targets: ["AmazonBedrockProvider"]),
        .library(name: "GatewayProvider", targets: ["GatewayProvider"]),
        .library(name: "GoogleProvider", targets: ["GoogleProvider"]),
        .library(name: "GoogleVertexProvider", targets: ["GoogleVertexProvider"]),
        .library(name: "AzureProvider", targets: ["AzureProvider"]),
        .library(name: "GroqProvider", targets: ["GroqProvider"]),
        .library(name: "MistralProvider", targets: ["MistralProvider"]),
        .library(name: "PerplexityProvider", targets: ["PerplexityProvider"]),
        .library(name: "CohereProvider", targets: ["CohereProvider"]),
        .library(name: "DeepgramProvider", targets: ["DeepgramProvider"]),
        .library(name: "DeepInfraProvider", targets: ["DeepInfraProvider"]),
        .library(name: "ElevenLabsProvider", targets: ["ElevenLabsProvider"]),
        .library(name: "FalProvider", targets: ["FalProvider"]),
        .library(name: "FireworksProvider", targets: ["FireworksProvider"]),
        .library(name: "GladiaProvider", targets: ["GladiaProvider"]),
        .library(name: "HuggingFaceProvider", targets: ["HuggingFaceProvider"]),
        .library(name: "HumeProvider", targets: ["HumeProvider"]),
        .library(name: "AssemblyAIProvider", targets: ["AssemblyAIProvider"]),
        .library(name: "CerebrasProvider", targets: ["CerebrasProvider"]),
        .library(name: "DeepSeekProvider", targets: ["DeepSeekProvider"]),
        .library(name: "BasetenProvider", targets: ["BasetenProvider"]),
        .library(name: "BlackForestLabsProvider", targets: ["BlackForestLabsProvider"]),
        .library(name: "ReplicateProvider", targets: ["ReplicateProvider"]),
        .library(name: "XAIProvider", targets: ["XAIProvider"]),
        .library(name: "LMNTProvider", targets: ["LMNTProvider"]),
        .library(name: "LumaProvider", targets: ["LumaProvider"]),
        .library(name: "TogetherAIProvider", targets: ["TogetherAIProvider"]),
        .library(name: "ProdiaProvider", targets: ["ProdiaProvider"]),
        .library(name: "RevAIProvider", targets: ["RevAIProvider"]),
        .library(name: "VercelProvider", targets: ["VercelProvider"]),
        .library(name: "AISDKJSONSchema", targets: ["AISDKJSONSchema"]),
        .library(name: "EventSourceParser", targets: ["EventSourceParser"]), // internal lib for SSE
        .library(name: "AISDKZodAdapter", targets: ["AISDKZodAdapter"]),
        .executable(name: "playground", targets: ["SwiftAISDKPlayground"]) 
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        // EventSourceParser - SSE parsing (internal utility)
        .target(name: "EventSourceParser"),
        .testTarget(name: "EventSourceParserTests", dependencies: ["EventSourceParser"]),

        // AISDKProvider - Foundation types (matches @ai-sdk/provider)
        // Language model interfaces (V2/V3), provider errors, JSONValue, shared types
        .target(name: "AISDKProvider", dependencies: []),
        .testTarget(name: "AISDKProviderTests", dependencies: ["AISDKProvider"]),

        // AISDKProviderUtils - Provider utilities (matches @ai-sdk/provider-utils)
        // HTTP, JSON, schema, validation, retry, headers, ID generation, tools
        .target(
            name: "AISDKProviderUtils",
            dependencies: ["AISDKProvider", "AISDKZodAdapter", "EventSourceParser"]
        ),
        .testTarget(name: "AISDKProviderUtilsTests", dependencies: ["AISDKProviderUtils", "AISDKZodAdapter"]),

        // Zod/ToJSONSchema adapters (public)
        .target(name: "AISDKZodAdapter", dependencies: ["AISDKProvider"]),

        // OpenAI provider package
        .target(name: "OpenAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),

        // OpenAI-compatible provider package
        .target(name: "OpenAICompatibleProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "AnthropicProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "AmazonBedrockProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "AnthropicProvider"]),
        .target(name: "GatewayProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "GoogleProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "GoogleVertexProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "GoogleProvider"]),
        .target(name: "AzureProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAIProvider"]),
        .target(name: "GroqProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "MistralProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "PerplexityProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "CohereProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "DeepgramProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "DeepInfraProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "ElevenLabsProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "FalProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "FireworksProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "GladiaProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "HuggingFaceProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "HumeProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "AssemblyAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "CerebrasProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "DeepSeekProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "BasetenProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "BlackForestLabsProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "ReplicateProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "XAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "LMNTProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "LumaProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "TogetherAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "ProdiaProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "RevAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "VercelProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        // JSON Schema generator (optional product)
        .target(
            name: "AISDKJSONSchema",
            dependencies: [
                "AISDKProviderUtils",
                "AISDKZodAdapter"
            ]
        ),
        .testTarget(name: "AISDKJSONSchemaTests", dependencies: ["AISDKJSONSchema", "AISDKProviderUtils"]),

        // SwiftAISDK - Main AI SDK (matches @ai-sdk/ai)
        // GenerateText, Registry, Middleware, Prompts, Tools, Telemetry
        .target(name: "SwiftAISDK", dependencies: ["AISDKProvider", "AISDKProviderUtils", "AISDKJSONSchema", "EventSourceParser", "GatewayProvider"]),
        .testTarget(name: "SwiftAISDKTests", dependencies: ["SwiftAISDK", "OpenAIProvider", "OpenAICompatibleProvider", "CohereProvider", "AmazonBedrockProvider"]),
        .testTarget(name: "OpenAICompatibleProviderTests", dependencies: ["OpenAICompatibleProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "AnthropicProviderTests", dependencies: ["AnthropicProvider", "AISDKProvider", "AISDKProviderUtils"], resources: [.copy("Fixtures")]),
        .testTarget(name: "GoogleProviderTests", dependencies: ["GoogleProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "GoogleVertexProviderTests", dependencies: ["GoogleVertexProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "GroqProviderTests", dependencies: ["GroqProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "MistralProviderTests", dependencies: ["MistralProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "XAIProviderTests", dependencies: ["XAIProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "AzureProviderTests", dependencies: ["AzureProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAIProvider"]),
        .testTarget(name: "CerebrasProviderTests", dependencies: ["CerebrasProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .testTarget(name: "DeepSeekProviderTests", dependencies: ["DeepSeekProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .testTarget(name: "BasetenProviderTests", dependencies: ["BasetenProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .testTarget(name: "BlackForestLabsProviderTests", dependencies: ["BlackForestLabsProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "LMNTProviderTests", dependencies: ["LMNTProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "ReplicateProviderTests", dependencies: ["ReplicateProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "TogetherAIProviderTests", dependencies: ["TogetherAIProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "ProdiaProviderTests", dependencies: ["ProdiaProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "RevAIProviderTests", dependencies: ["RevAIProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "VercelProviderTests", dependencies: ["VercelProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),

        // SwiftAISDKPlayground - CLI executable for manual testing (Playground)
        .executableTarget(
            name: "SwiftAISDKPlayground",
            dependencies: [
                "SwiftAISDK",
                "AISDKProvider",
                "AISDKProviderUtils",
                "OpenAIProvider",
                "GoogleProvider",
                "GoogleVertexProvider",
                "AzureProvider",
                "GroqProvider",
                "MistralProvider",
                "PerplexityProvider",
                "CohereProvider",
                "DeepgramProvider",
                "DeepInfraProvider",
                "ElevenLabsProvider",
                "FalProvider",
                "FireworksProvider",
                "GladiaProvider",
                "HuggingFaceProvider",
                "HumeProvider",
                "AssemblyAIProvider",
                "CerebrasProvider",
                "DeepSeekProvider",
                "BlackForestLabsProvider",
                "ReplicateProvider",
                "LMNTProvider",
                "LumaProvider",
                "TogetherAIProvider",
                "XAIProvider",
                "ProdiaProvider",
                "RevAIProvider",
                "VercelProvider",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]
        )
    ]
)
