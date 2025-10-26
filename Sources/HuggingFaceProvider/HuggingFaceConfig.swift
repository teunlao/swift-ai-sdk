import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/huggingface-config.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct HuggingFaceConfig: Sendable {
    struct RequestOptions: Sendable {
        let modelId: String
        let path: String
    }

    let provider: String
    let url: @Sendable (RequestOptions) -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let generateId: (@Sendable () -> String)?

    init(
        provider: String,
        url: @escaping @Sendable (RequestOptions) -> String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        generateId: (@Sendable () -> String)?
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}
