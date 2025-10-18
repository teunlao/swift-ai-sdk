import Foundation
import AISDKProviderUtils

/// Configuration options for OpenAI provider API calls.
///
/// Mirrors `packages/openai/src/openai-config.ts`.
public struct OpenAIConfig: @unchecked Sendable {
    public struct InternalOptions: Sendable {
        public let currentDate: (@Sendable () -> Date)?

        public init(currentDate: (@Sendable () -> Date)? = nil) {
            self.currentDate = currentDate
        }
    }

    public struct URLOptions: Sendable {

        public let modelId: String
        public let path: String

        public init(modelId: String, path: String) {
            self.modelId = modelId
            self.path = path
        }
    }

    public let provider: String
    public let url: @Sendable (_ options: URLOptions) -> String
    public let headers: @Sendable () -> [String: String?]
    public let fetch: FetchFunction?
    public let generateId: (@Sendable () -> String)?
    public let fileIdPrefixes: [String]?
    public let _internal: InternalOptions?

    public init(
        provider: String,
        url: @escaping @Sendable (_ options: URLOptions) -> String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction? = nil,
        generateId: (@Sendable () -> String)? = nil,
        fileIdPrefixes: [String]? = nil,
        _internal: InternalOptions? = nil
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
        self.fileIdPrefixes = fileIdPrefixes
        self._internal = _internal
    }
}
