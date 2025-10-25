import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-chat-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct MistralChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension MistralChatModelId {
    // Premier
    static let ministral3bLatest: Self = "ministral-3b-latest"
    static let ministral8bLatest: Self = "ministral-8b-latest"
    static let mistralLargeLatest: Self = "mistral-large-latest"
    static let mistralMediumLatest: Self = "mistral-medium-latest"
    static let mistralMedium2508: Self = "mistral-medium-2508"
    static let mistralMedium2505: Self = "mistral-medium-2505"
    static let mistralSmallLatest: Self = "mistral-small-latest"
    static let pixtralLargeLatest: Self = "pixtral-large-latest"

    // Reasoning models
    static let magistralSmall2507: Self = "magistral-small-2507"
    static let magistralMedium2507: Self = "magistral-medium-2507"
    static let magistralSmall2506: Self = "magistral-small-2506"
    static let magistralMedium2506: Self = "magistral-medium-2506"

    // Free
    static let pixtral12b2409: Self = "pixtral-12b-2409"

    // Legacy
    static let openMistral7b: Self = "open-mistral-7b"
    static let openMixtral8x7b: Self = "open-mixtral-8x7b"
    static let openMixtral8x22b: Self = "open-mixtral-8x22b"
}

public struct MistralEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension MistralEmbeddingModelId {
    static let mistralEmbed: Self = "mistral-embed"
}
