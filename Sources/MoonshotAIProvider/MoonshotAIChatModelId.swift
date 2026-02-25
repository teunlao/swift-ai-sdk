import Foundation

/// Represents MoonshotAI chat model identifiers.
/// Mirrors `packages/moonshotai/src/moonshotai-chat-options.ts`.
public struct MoonshotAIChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension MoonshotAIChatModelId {
    static let moonshotV18k: Self = "moonshot-v1-8k"
    static let moonshotV132k: Self = "moonshot-v1-32k"
    static let moonshotV1128k: Self = "moonshot-v1-128k"
    static let kimiK2: Self = "kimi-k2"
    static let kimiK20905: Self = "kimi-k2-0905"
    static let kimiK2Thinking: Self = "kimi-k2-thinking"
    static let kimiK2ThinkingTurbo: Self = "kimi-k2-thinking-turbo"
    static let kimiK2Turbo: Self = "kimi-k2-turbo"
    static let kimiK25: Self = "kimi-k2.5"
}

