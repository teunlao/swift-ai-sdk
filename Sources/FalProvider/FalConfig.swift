import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Inspired by packages/fal/src/fal-config.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct FalConfig: Sendable {
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
    public let headers: @Sendable () -> [String: String?]
    public let fetch: FetchFunction?
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        url: @escaping @Sendable (RequestOptions) -> String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}
