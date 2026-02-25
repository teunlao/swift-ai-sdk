import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/open-responses/src/responses/open-responses-config.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct OpenResponsesConfig: Sendable {
    public let provider: String
    public let url: String
    public let headers: @Sendable () -> [String: String]
    public let fetch: FetchFunction?
    public let generateId: IDGenerator

    public init(
        provider: String,
        url: String,
        headers: @escaping @Sendable () -> [String: String],
        fetch: FetchFunction? = nil,
        generateId: @escaping IDGenerator
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

