/**
 Mock implementation of LanguageModelV3 for testing.

 Port of `@ai-sdk/ai/src/test/mock-language-model-v3.ts`.

 This mock records all calls to `doGenerate` and `doStream` and supports
 configurable behavior via closures, single values, or arrays of values.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Mock implementation of LanguageModelV3 protocol for testing purposes.
///
/// Supports three modes for doGenerate and doStream:
/// - Function: Execute custom logic for each call
/// - Single value: Return the same value for all calls
/// - Array: Return values sequentially by call index
public final class MockLanguageModelV3: LanguageModelV3, @unchecked Sendable {
    public let specificationVersion: String = "v3"
    public let provider: String
    public let modelId: String

    /// Recorded calls to doGenerate
    public private(set) var doGenerateCalls: [LanguageModelV3CallOptions] = []

    /// Recorded calls to doStream
    public private(set) var doStreamCalls: [LanguageModelV3CallOptions] = []

    private let supportedUrlsProvider: () async throws -> [String: [NSRegularExpression]]
    private let generateBehavior: GenerateBehavior
    private let streamBehavior: StreamBehavior

    /// Behavior type for doGenerate
    private enum GenerateBehavior {
        case function((LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult)
        case singleValue(LanguageModelV3GenerateResult)
        case array([LanguageModelV3GenerateResult])
    }

    /// Behavior type for doStream
    private enum StreamBehavior {
        case function((LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult)
        case singleValue(LanguageModelV3StreamResult)
        case array([LanguageModelV3StreamResult])
    }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await supportedUrlsProvider()
        }
    }

    /// Initialize mock language model with configurable behavior.
    ///
    /// - Parameters:
    ///   - provider: Provider name (default: "mock-provider")
    ///   - modelId: Model identifier (default: "mock-model-id")
    ///   - supportedUrls: Supported URL configuration, can be static value or function
    ///   - doGenerate: Behavior for doGenerate - can be function, single value, or array
    ///   - doStream: Behavior for doStream - can be function, single value, or array
    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        supportedUrls: SupportedUrlsConfig = .value([:]),
        doGenerate: DoGenerateConfig = .notImplemented,
        doStream: DoStreamConfig = .notImplemented
    ) {
        self.provider = provider
        self.modelId = modelId

        // Configure supportedUrls
        switch supportedUrls {
        case .value(let urls):
            self.supportedUrlsProvider = { urls }
        case .function(let fn):
            self.supportedUrlsProvider = fn
        }

        // Configure doGenerate behavior
        switch doGenerate {
        case .function(let fn):
            self.generateBehavior = .function(fn)
        case .singleValue(let result):
            self.generateBehavior = .singleValue(result)
        case .array(let results):
            self.generateBehavior = .array(results)
        case .notImplemented:
            self.generateBehavior = .function { _ in try notImplemented() }
        }

        // Configure doStream behavior
        switch doStream {
        case .function(let fn):
            self.streamBehavior = .function(fn)
        case .singleValue(let result):
            self.streamBehavior = .singleValue(result)
        case .array(let results):
            self.streamBehavior = .array(results)
        case .notImplemented:
            self.streamBehavior = .function { _ in try notImplemented() }
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        doGenerateCalls.append(options)

        switch generateBehavior {
        case .function(let fn):
            return try await fn(options)
        case .singleValue(let result):
            return result
        case .array(let results):
            let index = doGenerateCalls.count - 1
            return results[index]
        }
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        doStreamCalls.append(options)

        switch streamBehavior {
        case .function(let fn):
            return try await fn(options)
        case .singleValue(let result):
            return result
        case .array(let results):
            let index = doStreamCalls.count - 1
            return results[index]
        }
    }
}

// MARK: - Configuration Types

extension MockLanguageModelV3 {
    /// Configuration for supportedUrls
    public enum SupportedUrlsConfig {
        case value([String: [NSRegularExpression]])
        case function(() async throws -> [String: [NSRegularExpression]])
    }

    /// Configuration for doGenerate behavior
    public enum DoGenerateConfig {
        case function((LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult)
        case singleValue(LanguageModelV3GenerateResult)
        case array([LanguageModelV3GenerateResult])
        case notImplemented
    }

    /// Configuration for doStream behavior
    public enum DoStreamConfig {
        case function((LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult)
        case singleValue(LanguageModelV3StreamResult)
        case array([LanguageModelV3StreamResult])
        case notImplemented
    }
}
