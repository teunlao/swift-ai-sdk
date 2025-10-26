import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/hume/src/hume-config.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct HumeConfig: Sendable {
    let provider: String
    let url: @Sendable (_ options: (modelId: String, path: String)) -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let generateId: (@Sendable () -> String)?

    init(
        provider: String,
        url: @escaping @Sendable (_ options: (modelId: String, path: String)) -> String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        generateId: (@Sendable () -> String)? = nil
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}
