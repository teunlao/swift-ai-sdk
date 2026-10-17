import Foundation
import AISDKProviderUtils

public struct ElevenLabsConfig: Sendable {
    public struct RequestOptions: Sendable {
        public let modelId: String
        public let path: String

        public init(modelId: String, path: String) {
            self.modelId = modelId
            self.path = path
        }
    }

    public let provider: String
    public let url: @Sendable (RequestOptions) -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public let webSocket: WebSocketConstructor?
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        url: @escaping @Sendable (RequestOptions) -> String,
        headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
        fetch: FetchFunction? = nil,
        webSocket: WebSocketConstructor? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
        self.currentDate = currentDate
    }
}
