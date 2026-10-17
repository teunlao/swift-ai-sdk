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

    public struct ImageInputCapabilities: Sendable {
        public let supportsFileInputs: Bool?
        public let supportsMaskInputs: Bool?

        public init(supportsFileInputs: Bool? = nil, supportsMaskInputs: Bool? = nil) {
            self.supportsFileInputs = supportsFileInputs
            self.supportsMaskInputs = supportsMaskInputs
        }
    }

    public let provider: String
    public let baseURL: String?
    public let explicitMessageItemType: Bool?
    public let imageInputCapabilities: ImageInputCapabilities?
    public let url: @Sendable (_ options: URLOptions) throws -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public let webSocket: WebSocketConstructor?
    public let generateId: (@Sendable () -> String)?
    public let fileIdPrefixes: [String]?
    public let supportsWebSearchSourcesInclude: Bool?
    public let _internal: InternalOptions?

    public init(
        provider: String,
        baseURL: String? = nil,
        explicitMessageItemType: Bool? = nil,
        imageInputCapabilities: ImageInputCapabilities? = nil,
        url: @escaping @Sendable (_ options: URLOptions) throws -> String,
        headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
        fetch: FetchFunction? = nil,
        webSocket: WebSocketConstructor? = nil,
        generateId: (@Sendable () -> String)? = nil,
        fileIdPrefixes: [String]? = nil,
        supportsWebSearchSourcesInclude: Bool? = nil,
        _internal: InternalOptions? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.explicitMessageItemType = explicitMessageItemType
        self.imageInputCapabilities = imageInputCapabilities
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
        self.generateId = generateId
        self.fileIdPrefixes = fileIdPrefixes
        self.supportsWebSearchSourcesInclude = supportsWebSearchSourcesInclude
        self._internal = _internal
    }
}
