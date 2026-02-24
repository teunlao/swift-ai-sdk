import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-options.ts
// Ported from packages/google-vertex/src/google-vertex-embedding-options.ts
// Ported from packages/google-vertex/src/google-vertex-image-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GoogleVertexModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct GoogleVertexEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct GoogleVertexImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct GoogleVertexVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known model identifiers

public extension GoogleVertexModelId {
    // Stable models — https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions
    static let gemini25Pro: Self = "gemini-2.5-pro"
    static let gemini25Flash: Self = "gemini-2.5-flash"
    static let gemini25FlashLite: Self = "gemini-2.5-flash-lite"
    static let gemini20FlashLite: Self = "gemini-2.0-flash-lite"
    static let gemini20Flash: Self = "gemini-2.0-flash"
    static let gemini20Flash001: Self = "gemini-2.0-flash-001"
    static let gemini15Flash: Self = "gemini-1.5-flash"
    static let gemini15Flash001: Self = "gemini-1.5-flash-001"
    static let gemini15Flash002: Self = "gemini-1.5-flash-002"
    static let gemini15Pro: Self = "gemini-1.5-pro"
    static let gemini15Pro001: Self = "gemini-1.5-pro-001"
    static let gemini15Pro002: Self = "gemini-1.5-pro-002"
    static let gemini10Pro001: Self = "gemini-1.0-pro-001"
    static let gemini10ProVision001: Self = "gemini-1.0-pro-vision-001"
    static let gemini10Pro: Self = "gemini-1.0-pro"
    static let gemini10Pro002: Self = "gemini-1.0-pro-002"

    // Preview models
    static let gemini20FlashLitePreview0205: Self = "gemini-2.0-flash-lite-preview-02-05"
    static let gemini25FlashLitePreview092025: Self = "gemini-2.5-flash-lite-preview-09-2025"
    static let gemini25FlashPreview092025: Self = "gemini-2.5-flash-preview-09-2025"
    static let gemini31ProPreview: Self = "gemini-3.1-pro-preview"
    static let gemini3ProPreview: Self = "gemini-3-pro-preview"
    static let gemini3ProImagePreview: Self = "gemini-3-pro-image-preview"
    static let gemini3FlashPreview: Self = "gemini-3-flash-preview"

    // Experimental models
    static let gemini20ProExp0205: Self = "gemini-2.0-pro-exp-02-05"
    static let gemini20FlashExp: Self = "gemini-2.0-flash-exp"
}

public extension GoogleVertexEmbeddingModelId {
    static let textEmbeddingGecko: Self = "textembedding-gecko"
    static let textEmbeddingGecko001: Self = "textembedding-gecko@001"
    static let textEmbeddingGecko003: Self = "textembedding-gecko@003"
    static let textEmbeddingGeckoMultilingual: Self = "textembedding-gecko-multilingual"
    static let textEmbeddingGeckoMultilingual001: Self = "textembedding-gecko-multilingual@001"
    static let textMultilingualEmbedding002: Self = "text-multilingual-embedding-002"
    static let textEmbedding004: Self = "text-embedding-004"
    static let textEmbedding005: Self = "text-embedding-005"
}

public extension GoogleVertexImageModelId {
    static let imagen30Generate001: Self = "imagen-3.0-generate-001"
    static let imagen30Generate002: Self = "imagen-3.0-generate-002"
    static let imagen30FastGenerate001: Self = "imagen-3.0-fast-generate-001"
    static let imagen40Generate001: Self = "imagen-4.0-generate-001"
    static let imagen40FastGenerate001: Self = "imagen-4.0-fast-generate-001"
    static let imagen40UltraGenerate001: Self = "imagen-4.0-ultra-generate-001"
    static let gemini25FlashImage: Self = "gemini-2.5-flash-image"
    static let gemini3ProImagePreview: Self = "gemini-3-pro-image-preview"

    @available(*, deprecated, message: "Use `imagen40Generate001`.")
    static let imagen40GeneratePreview0606: Self = "imagen-4.0-generate-preview-06-06"

    @available(*, deprecated, message: "Use `imagen40FastGenerate001`.")
    static let imagen40FastGeneratePreview0606: Self = "imagen-4.0-fast-generate-preview-06-06"

    @available(*, deprecated, message: "Use `imagen40UltraGenerate001`.")
    static let imagen40UltraGeneratePreview0606: Self = "imagen-4.0-ultra-generate-preview-06-06"
}

public extension GoogleVertexVideoModelId {
    static let veo20GeneratePreview: Self = "veo-2.0-generate-preview"
    static let veo20GenerateExp: Self = "veo-2.0-generate-exp"
    static let veo20Generate001: Self = "veo-2.0-generate-001"
    static let veo30Generate001: Self = "veo-3.0-generate-001"
    static let veo30FastGenerate001: Self = "veo-3.0-fast-generate-001"
    static let veo30GeneratePreview: Self = "veo-3.0-generate-preview"
    static let veo30FastGeneratePreview: Self = "veo-3.0-fast-generate-preview"
    static let veo31Generate001: Self = "veo-3.1-generate-001"
    static let veo31FastGenerate001: Self = "veo-3.1-fast-generate-001"
    static let veo31GeneratePreview: Self = "veo-3.1-generate-preview"
    static let veo31FastGeneratePreview: Self = "veo-3.1-fast-generate-preview"
}
