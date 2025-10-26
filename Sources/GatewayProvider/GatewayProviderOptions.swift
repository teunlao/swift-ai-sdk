import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-provider-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GatewayProviderOptions: Sendable, Codable, Equatable {
    /// Array of provider slugs that are the only ones allowed to be used.
    public let only: [String]?

    /// Array of provider slugs specifying the sequence in which providers should be attempted.
    public let order: [String]?

    /// The unique identifier for the end user on behalf of whom the request was made.
    public let user: String?

    /// User-specified tags for reporting and usage filtering.
    public let tags: [String]?

    public init(only: [String]? = nil, order: [String]? = nil, user: String? = nil, tags: [String]? = nil) {
        self.only = only
        self.order = order
        self.user = user
        self.tags = tags
    }
}
