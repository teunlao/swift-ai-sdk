/**
 Mock implementation of LanguageModelV4 for testing.

 Port direction: mirrors the Swift V3 mock while exercising the current
 upstream V4 language model contract.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Mock implementation of LanguageModelV4 protocol for testing purposes.
///
/// Supports three modes for doGenerate and doStream:
/// - Function: Execute custom logic for each call
/// - Single value: Return the same value for all calls
/// - Array: Return values sequentially by call index
public final class MockLanguageModelV4: LanguageModelV4, @unchecked Sendable {
    public let specificationVersion: String = "v4"
    public let provider: String
    public let modelId: String

    /// Recorded calls to doGenerate.
    public private(set) var doGenerateCalls: [LanguageModelV4CallOptions] = []

    /// Recorded calls to doStream.
    public private(set) var doStreamCalls: [LanguageModelV4CallOptions] = []

    private let supportedUrlsProvider: () async throws -> [String: [NSRegularExpression]]
    private let generateBehavior: GenerateBehavior
    private let streamBehavior: StreamBehavior

    private enum GenerateBehavior {
        case function((LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult)
        case singleValue(LanguageModelV4GenerateResult)
        case array([LanguageModelV4GenerateResult])
    }

    private enum StreamBehavior {
        case function((LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult)
        case singleValue(LanguageModelV4StreamResult)
        case array([LanguageModelV4StreamResult])
    }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await supportedUrlsProvider()
        }
    }

    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        supportedUrls: SupportedUrlsConfig = .value([:]),
        doGenerate: DoGenerateConfig = .notImplemented,
        doStream: DoStreamConfig = .notImplemented
    ) {
        self.provider = provider
        self.modelId = modelId

        switch supportedUrls {
        case .value(let urls):
            self.supportedUrlsProvider = { urls }
        case .function(let fn):
            self.supportedUrlsProvider = fn
        }

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

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
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

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
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

extension MockLanguageModelV4 {
    /// Configuration for supportedUrls.
    public enum SupportedUrlsConfig {
        case value([String: [NSRegularExpression]])
        case function(() async throws -> [String: [NSRegularExpression]])
    }

    /// Configuration for doGenerate behavior.
    public enum DoGenerateConfig {
        case function((LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult)
        case singleValue(LanguageModelV4GenerateResult)
        case array([LanguageModelV4GenerateResult])
        case notImplemented
    }

    /// Configuration for doStream behavior.
    public enum DoStreamConfig {
        case function((LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult)
        case singleValue(LanguageModelV4StreamResult)
        case array([LanguageModelV4StreamResult])
        case notImplemented
    }
}
