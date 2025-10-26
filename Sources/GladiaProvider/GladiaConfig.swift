import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gladia/src/gladia-config.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct GladiaConfig: Sendable {
    struct RequestOptions: Sendable {
        let modelId: String
        let path: String
    }

    let provider: String
    let url: @Sendable (RequestOptions) -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        url: @escaping @Sendable (RequestOptions) -> String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}
