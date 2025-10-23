import Foundation

/// Represents DeepSeek chat model identifiers.
/// Mirrors `packages/deepseek/src/deepseek-chat-options.ts`.
public struct DeepSeekChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension DeepSeekChatModelId {
    /// Known DeepSeek chat models: https://api-docs.deepseek.com/quick_start/pricing
    static let deepseekChat: Self = "deepseek-chat"
    static let deepseekReasoner: Self = "deepseek-reasoner"
}
