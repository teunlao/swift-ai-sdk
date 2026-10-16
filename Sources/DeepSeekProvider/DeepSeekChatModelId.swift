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
    static let deepseekFlash: Self = "deepseek-flash"
    static let deepseekV4Flash: Self = "deepseek-v4-flash"
    static let deepseekV4Pro: Self = "deepseek-v4-pro"
    static let deepseekV4FlashVisionExp: Self = "deepseek-v4-flash-vision-exp"
}
