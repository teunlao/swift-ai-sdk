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
    static let moonshotV1Auto: Self = "moonshot-v1-auto"
    static let moonshotV18kVisionPreview: Self = "moonshot-v1-8k-vision-preview"
    static let moonshotV132kVisionPreview: Self = "moonshot-v1-32k-vision-preview"
    static let moonshotV1128kVisionPreview: Self = "moonshot-v1-128k-vision-preview"
    static let kimiK25: Self = "kimi-k2.5"
    static let kimiK26: Self = "kimi-k2.6"
    static let kimiK27Code: Self = "kimi-k2.7-code"
    static let kimiK27CodeHighspeed: Self = "kimi-k2.7-code-highspeed"
    static let kimiK3: Self = "kimi-k3"
}

