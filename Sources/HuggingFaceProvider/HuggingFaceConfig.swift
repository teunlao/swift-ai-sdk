import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/huggingface-config.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

struct HuggingFaceConfig: Sendable {
    struct RequestOptions: Sendable {
        let modelId: String
        let path: String
    }

    let provider: String
    let url: @Sendable (RequestOptions) -> String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let generateId: (@Sendable () -> String)?

    init(
        provider: String,
        url: @escaping @Sendable (RequestOptions) -> String,
        headers: @escaping @Sendable () throws -> [String: String?],
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
