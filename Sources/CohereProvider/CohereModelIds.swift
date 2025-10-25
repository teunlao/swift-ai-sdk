import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-chat-options.ts and
// packages/cohere/src/cohere-embedding-options.ts (model identifiers)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct CohereChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension CohereChatModelId {
    static let commandA032025: Self = "command-a-03-2025"
    static let commandAReasoning082025: Self = "command-a-reasoning-08-2025"
    static let commandR7b122024: Self = "command-r7b-12-2024"
    static let commandRPlus042024: Self = "command-r-plus-04-2024"
    static let commandRPlus: Self = "command-r-plus"
    static let commandR082024: Self = "command-r-08-2024"
    static let commandR032024: Self = "command-r-03-2024"
    static let commandR: Self = "command-r"
    static let command: Self = "command"
    static let commandNightly: Self = "command-nightly"
    static let commandLight: Self = "command-light"
    static let commandLightNightly: Self = "command-light-nightly"
}

public struct CohereEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension CohereEmbeddingModelId {
    static let embedEnglishV3: Self = "embed-english-v3.0"
    static let embedMultilingualV3: Self = "embed-multilingual-v3.0"
    static let embedEnglishLightV3: Self = "embed-english-light-v3.0"
    static let embedMultilingualLightV3: Self = "embed-multilingual-light-v3.0"
    static let embedEnglishV2: Self = "embed-english-v2.0"
    static let embedEnglishLightV2: Self = "embed-english-light-v2.0"
    static let embedMultilingualV2: Self = "embed-multilingual-v2.0"
}
