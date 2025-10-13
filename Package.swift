// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAISDK",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        // Main products matching upstream @ai-sdk architecture
        .library(name: "AISDKProvider", targets: ["AISDKProvider"]),
        .library(name: "AISDKProviderUtils", targets: ["AISDKProviderUtils"]),
        .library(name: "SwiftAISDK", targets: ["SwiftAISDK"]),
        .library(name: "EventSourceParser", targets: ["EventSourceParser"]) // internal lib for SSE
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
        .target(name: "AISDKProviderUtils", dependencies: ["AISDKProvider"]),
        .testTarget(name: "AISDKProviderUtilsTests", dependencies: ["AISDKProviderUtils"]),

        // SwiftAISDK - Main AI SDK (matches @ai-sdk/ai)
        // GenerateText, Registry, Middleware, Prompts, Tools, Telemetry
        .target(name: "SwiftAISDK", dependencies: ["AISDKProvider", "AISDKProviderUtils", "EventSourceParser"]),
        .testTarget(name: "SwiftAISDKTests", dependencies: ["SwiftAISDK"]),
    ]
)
