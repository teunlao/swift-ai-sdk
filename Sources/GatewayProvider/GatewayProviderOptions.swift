import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-provider-options.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

public struct GatewayLanguageModelOptions: Sendable, Codable, Equatable {
    /// Array of provider slugs that are the only ones allowed to be used.
    public let only: [String]?

    /// Array of provider slugs specifying the sequence in which providers should be attempted.
    public let order: [String]?

    /// The unique identifier for the end user on behalf of whom the request was made.
    public let user: String?

    /// User-specified tags for reporting and usage filtering.
    public let tags: [String]?

    /// Array of model slugs specifying fallback models to use in order.
    public let models: [String]?

    /// Request-scoped BYOK credentials (provider -> credential list).
    public let byok: [String: [[String: JSONValue]] ]?

    /// Whether to filter by only providers that state they have zero data retention.
    public let zeroDataRetention: Bool?

    public init(
        only: [String]? = nil,
        order: [String]? = nil,
        user: String? = nil,
        tags: [String]? = nil,
        models: [String]? = nil,
        byok: [String: [[String: JSONValue]]]? = nil,
        zeroDataRetention: Bool? = nil
    ) {
        self.only = only
        self.order = order
        self.user = user
        self.tags = tags
        self.models = models
        self.byok = byok
        self.zeroDataRetention = zeroDataRetention
    }
}

/// Deprecated upstream alias.
@available(*, deprecated, renamed: "GatewayLanguageModelOptions")
public typealias GatewayProviderOptions = GatewayLanguageModelOptions
