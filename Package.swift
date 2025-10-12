// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAISDK",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(name: "SwiftAISDK", targets: ["SwiftAISDK"]),
        .library(name: "EventSourceParser", targets: ["EventSourceParser"]) // internal lib for SSE
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "EventSourceParser"),
        .testTarget(name: "EventSourceParserTests", dependencies: ["EventSourceParser"]),
        .target(name: "SwiftAISDK", dependencies: ["EventSourceParser"]),
        .testTarget(name: "SwiftAISDKTests", dependencies: ["SwiftAISDK"]),
    ]
)
