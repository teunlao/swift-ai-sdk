import Foundation
import AISDKProviderUtils

// Port of packages/revai/src/revai-config.ts.

struct RevAIConfig: Sendable {
    struct RequestOptions: Sendable {
        let modelId: String
        let path: String
    }

    let provider: String
    let url: @Sendable (RequestOptions) -> String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        url: @escaping @Sendable (RequestOptions) -> String,
        headers: @escaping @Sendable () throws -> [String: String?],
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

