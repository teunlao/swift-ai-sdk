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
        .library(name: "GoogleProvider", targets: ["GoogleProvider"]),
        .library(name: "AzureProvider", targets: ["AzureProvider"]),
        .library(name: "GroqProvider", targets: ["GroqProvider"]),
        .library(name: "CerebrasProvider", targets: ["CerebrasProvider"]),
        .library(name: "DeepSeekProvider", targets: ["DeepSeekProvider"]),
        .library(name: "BasetenProvider", targets: ["BasetenProvider"]),
        .library(name: "ReplicateProvider", targets: ["ReplicateProvider"]),
        .library(name: "XAIProvider", targets: ["XAIProvider"]),
        .library(name: "LMNTProvider", targets: ["LMNTProvider"]),
        .library(name: "AISDKJSONSchema", targets: ["AISDKJSONSchema"]),
        .library(name: "EventSourceParser", targets: ["EventSourceParser"]), // internal lib for SSE
        .library(name: "AISDKZodAdapter", targets: ["AISDKZodAdapter"]),
        .executable(name: "playground", targets: ["SwiftAISDKPlayground"]) 
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/mattpolzin/OpenAPIKit", from: "3.0.0"),
        .package(url: "https://github.com/mattpolzin/OpenAPIReflection", from: "2.0.0")
    ],
    targets: [
        .plugin(
            name: "GenerateReleaseVersionPlugin",
            capability: .buildTool()
        ),
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
            dependencies: ["AISDKProvider", "AISDKZodAdapter"],
            plugins: ["GenerateReleaseVersionPlugin"]
        ),
        .testTarget(name: "AISDKProviderUtilsTests", dependencies: ["AISDKProviderUtils", "AISDKZodAdapter"]),

        // Zod/ToJSONSchema adapters (public)
        .target(name: "AISDKZodAdapter", dependencies: ["AISDKProvider"]),

        // OpenAI provider package
        .target(name: "OpenAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),

        // OpenAI-compatible provider package
        .target(name: "OpenAICompatibleProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "AnthropicProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "GoogleProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "AzureProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAIProvider"]),
        .target(name: "GroqProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .target(name: "CerebrasProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "DeepSeekProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "BasetenProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "ReplicateProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "XAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "LMNTProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        // JSON Schema generator (optional product)
        .target(
            name: "AISDKJSONSchema",
            dependencies: [
                "AISDKProviderUtils",
                "AISDKZodAdapter",
                .product(name: "OpenAPIKit", package: "OpenAPIKit"),
                .product(name: "OpenAPIReflection", package: "OpenAPIReflection")
            ]
        ),
        .testTarget(name: "AISDKJSONSchemaTests", dependencies: ["AISDKJSONSchema", "AISDKProviderUtils"]),

        // SwiftAISDK - Main AI SDK (matches @ai-sdk/ai)
        // GenerateText, Registry, Middleware, Prompts, Tools, Telemetry
        .target(name: "SwiftAISDK", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .testTarget(name: "SwiftAISDKTests", dependencies: ["SwiftAISDK", "OpenAIProvider", "OpenAICompatibleProvider"]),
        .testTarget(name: "OpenAICompatibleProviderTests", dependencies: ["OpenAICompatibleProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "AnthropicProviderTests", dependencies: ["AnthropicProvider", "AISDKProvider", "AISDKProviderUtils"], resources: [.copy("Fixtures")]),
        .testTarget(name: "GoogleProviderTests", dependencies: ["GoogleProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "GroqProviderTests", dependencies: ["GroqProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "XAIProviderTests", dependencies: ["XAIProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "AzureProviderTests", dependencies: ["AzureProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAIProvider"]),
        .testTarget(name: "CerebrasProviderTests", dependencies: ["CerebrasProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .testTarget(name: "DeepSeekProviderTests", dependencies: ["DeepSeekProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .testTarget(name: "BasetenProviderTests", dependencies: ["BasetenProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .testTarget(name: "LMNTProviderTests", dependencies: ["LMNTProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "ReplicateProviderTests", dependencies: ["ReplicateProvider", "AISDKProvider", "AISDKProviderUtils"]),

        // SwiftAISDKPlayground - CLI executable for manual testing (Playground)
        .executableTarget(
            name: "SwiftAISDKPlayground",
            dependencies: [
                "SwiftAISDK",
                "AISDKProvider",
                "AISDKProviderUtils",
                "OpenAIProvider",
                "GoogleProvider",
                "AzureProvider",
                "GroqProvider",
                "CerebrasProvider",
                "DeepSeekProvider",
                "ReplicateProvider",
                "LMNTProvider",
                "XAIProvider",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]
        )
    ]
)
