import Foundation

/// Wrapper types for xAI model identifiers.
/// Mirrors `packages/xai/src/xai-chat-options.ts` and `xai-image-settings.ts`.
public struct XAIChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct XAIImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known model identifiers (mirrors packages/xai/src/xai-chat-options.ts)

public extension XAIChatModelId {
    static let grok4FastNonReasoning: Self = "grok-4-fast-non-reasoning"
    static let grok4FastReasoning: Self = "grok-4-fast-reasoning"
    static let grokCodeFast1: Self = "grok-code-fast-1"
    static let grok4: Self = "grok-4"
    static let grok40709: Self = "grok-4-0709"
    static let grok4Latest: Self = "grok-4-latest"
    static let grok3: Self = "grok-3"
    static let grok3Latest: Self = "grok-3-latest"
    static let grok3Fast: Self = "grok-3-fast"
    static let grok3FastLatest: Self = "grok-3-fast-latest"
    static let grok3Mini: Self = "grok-3-mini"
    static let grok3MiniLatest: Self = "grok-3-mini-latest"
    static let grok3MiniFast: Self = "grok-3-mini-fast"
    static let grok3MiniFastLatest: Self = "grok-3-mini-fast-latest"
    static let grok2Vision1212: Self = "grok-2-vision-1212"
    static let grok2Vision: Self = "grok-2-vision"
    static let grok2VisionLatest: Self = "grok-2-vision-latest"
    static let grok2Image1212: Self = "grok-2-image-1212"
    static let grok2Image: Self = "grok-2-image"
    static let grok2ImageLatest: Self = "grok-2-image-latest"
    static let grok21212: Self = "grok-2-1212"
    static let grok2: Self = "grok-2"
    static let grok2Latest: Self = "grok-2-latest"
    static let grokVisionBeta: Self = "grok-vision-beta"
    static let grokBeta: Self = "grok-beta"
}

public extension XAIImageModelId {
    static let grok2Image: Self = "grok-2-image"
}
