import Foundation

public struct GoogleGenerativeAIModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct GoogleGenerativeAIEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct GoogleGenerativeAIImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Model Constants

public extension GoogleGenerativeAIModelId {
    // Stable models
    // https://ai.google.dev/gemini-api/docs/models/gemini
    static let gemini15Flash: Self = "gemini-1.5-flash"
    static let gemini15FlashLatest: Self = "gemini-1.5-flash-latest"
    static let gemini15Flash001: Self = "gemini-1.5-flash-001"
    static let gemini15Flash002: Self = "gemini-1.5-flash-002"
    static let gemini15Flash8b: Self = "gemini-1.5-flash-8b"
    static let gemini15Flash8bLatest: Self = "gemini-1.5-flash-8b-latest"
    static let gemini15Flash8b001: Self = "gemini-1.5-flash-8b-001"
    static let gemini15Pro: Self = "gemini-1.5-pro"
    static let gemini15ProLatest: Self = "gemini-1.5-pro-latest"
    static let gemini15Pro001: Self = "gemini-1.5-pro-001"
    static let gemini15Pro002: Self = "gemini-1.5-pro-002"
    static let gemini20Flash: Self = "gemini-2.0-flash"
    static let gemini20Flash001: Self = "gemini-2.0-flash-001"
    static let gemini20FlashLive001: Self = "gemini-2.0-flash-live-001"
    static let gemini20FlashLite: Self = "gemini-2.0-flash-lite"
    static let gemini20ProExp0205: Self = "gemini-2.0-pro-exp-02-05"
    static let gemini20FlashThinkingExp0121: Self = "gemini-2.0-flash-thinking-exp-01-21"
    static let gemini20FlashExp: Self = "gemini-2.0-flash-exp"
    static let gemini25Pro: Self = "gemini-2.5-pro"
    static let gemini25Flash: Self = "gemini-2.5-flash"
    static let gemini25FlashImagePreview: Self = "gemini-2.5-flash-image-preview"
    static let gemini25FlashLite: Self = "gemini-2.5-flash-lite"
    static let gemini25FlashLitePreview092025: Self = "gemini-2.5-flash-lite-preview-09-2025"
    static let gemini25FlashPreview0417: Self = "gemini-2.5-flash-preview-04-17"
    static let gemini25FlashPreview092025: Self = "gemini-2.5-flash-preview-09-2025"

    // Latest versions
    // https://ai.google.dev/gemini-api/docs/models#latest
    static let geminiProLatest: Self = "gemini-pro-latest"
    static let geminiFlashLatest: Self = "gemini-flash-latest"
    static let geminiFlashLiteLatest: Self = "gemini-flash-lite-latest"

    // Experimental models
    // https://ai.google.dev/gemini-api/docs/models/experimental-models
    static let gemini25ProExp0325: Self = "gemini-2.5-pro-exp-03-25"
    static let geminiExp1206: Self = "gemini-exp-1206"
    static let gemma312bIt: Self = "gemma-3-12b-it"
    static let gemma327bIt: Self = "gemma-3-27b-it"
}

public extension GoogleGenerativeAIEmbeddingModelId {
    // Embedding models
    // https://ai.google.dev/gemini-api/docs/models/gemini#embedding
    static let geminiEmbedding001: Self = "gemini-embedding-001"
    static let textEmbedding004: Self = "text-embedding-004"
}

public extension GoogleGenerativeAIImageModelId {
    // Image generation models
    // https://ai.google.dev/gemini-api/docs/imagen#imagen-model
    static let imagen30Generate002: Self = "imagen-3.0-generate-002"
}
