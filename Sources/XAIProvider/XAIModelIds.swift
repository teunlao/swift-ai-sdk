import Foundation

public struct XAIImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let grokImagineImage: Self = "grok-imagine-image"
    public static let grokImagineImage20: Self = "grok-imagine-image-2.0"
    public static let grokImagineImagePro: Self = "grok-imagine-image-pro"
}

public struct XAIVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let grokImagineVideo: Self = "grok-imagine-video"
    public static let grokImagineVideo15: Self = "grok-imagine-video-1.5"
}

public struct XAIResponsesModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let grok420NonReasoning: Self = "grok-4.20-non-reasoning"
    public static let grok420Reasoning: Self = "grok-4.20-reasoning"
    public static let grok43: Self = "grok-4.3"
    public static let grok45: Self = "grok-4.5"
    public static let grok46: Self = "grok-4.6"
    public static let grok47: Self = "grok-4.7"
    public static let grokLatest: Self = "grok-latest"
}
