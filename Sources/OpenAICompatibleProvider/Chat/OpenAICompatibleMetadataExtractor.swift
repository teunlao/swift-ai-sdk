import Foundation
import AISDKProvider

public struct OpenAICompatibleStreamMetadataExtractor: Sendable {
    private let process: @Sendable (JSONValue) -> Void
    private let build: @Sendable () -> SharedV3ProviderMetadata?

    public init(
        processChunk: @escaping @Sendable (JSONValue) -> Void,
        buildMetadata: @escaping @Sendable () -> SharedV3ProviderMetadata?
    ) {
        self.process = processChunk
        self.build = buildMetadata
    }

    public func processChunk(_ chunk: JSONValue) {
        process(chunk)
    }

    public func buildMetadata() -> SharedV3ProviderMetadata? {
        build()
    }
}

public struct OpenAICompatibleMetadataExtractor: Sendable {
    private let extract: @Sendable (JSONValue) async throws -> SharedV3ProviderMetadata?
    private let makeStream: @Sendable () -> OpenAICompatibleStreamMetadataExtractor

    public init(
        extractMetadata: @escaping @Sendable (JSONValue) async throws -> SharedV3ProviderMetadata?,
        createStreamExtractor: @escaping @Sendable () -> OpenAICompatibleStreamMetadataExtractor
    ) {
        self.extract = extractMetadata
        self.makeStream = createStreamExtractor
    }

    public func extractMetadata(parsedBody: JSONValue) async throws -> SharedV3ProviderMetadata? {
        try await extract(parsedBody)
    }

    public func createStreamExtractor() -> OpenAICompatibleStreamMetadataExtractor {
        makeStream()
    }
}
