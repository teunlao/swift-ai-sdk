public struct GoogleModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}
public struct GoogleEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}
public struct GoogleImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}
public struct GoogleVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}
public typealias GoogleSpeechModelId = String

public extension GoogleModelId {
    static let gemini20Flash: Self = "gemini-2.0-flash"
    static let gemini20Flash001: Self = "gemini-2.0-flash-001"
    static let gemini20FlashLite: Self = "gemini-2.0-flash-lite"
    static let gemini20FlashLite001: Self = "gemini-2.0-flash-lite-001"
    static let gemini25Pro: Self = "gemini-2.5-pro"
    static let gemini25Flash: Self = "gemini-2.5-flash"
    static let gemini25FlashImage: Self = "gemini-2.5-flash-image"
    static let gemini25FlashLite: Self = "gemini-2.5-flash-lite"
    static let gemini25FlashPreviewTTS: Self = "gemini-2.5-flash-preview-tts"
    static let gemini25ProPreviewTTS: Self = "gemini-2.5-pro-preview-tts"
    static let gemini25FlashNativeAudioLatest: Self = "gemini-2.5-flash-native-audio-latest"
    static let gemini25FlashNativeAudioPreview092025: Self = "gemini-2.5-flash-native-audio-preview-09-2025"
    static let gemini25FlashNativeAudioPreview122025: Self = "gemini-2.5-flash-native-audio-preview-12-2025"
    static let gemini25ComputerUsePreview102025: Self = "gemini-2.5-computer-use-preview-10-2025"
    static let gemini3ProPreview: Self = "gemini-3-pro-preview"
    static let gemini3ProImagePreview: Self = "gemini-3-pro-image-preview"
    static let gemini3FlashPreview: Self = "gemini-3-flash-preview"
    static let gemini31ProPreview: Self = "gemini-3.1-pro-preview"
    static let gemini31ProPreviewCustomTools: Self = "gemini-3.1-pro-preview-customtools"
    static let gemini31FlashImagePreview: Self = "gemini-3.1-flash-image-preview"
    static let gemini31FlashLitePreview: Self = "gemini-3.1-flash-lite-preview"
    static let gemini31FlashTTSPreview: Self = "gemini-3.1-flash-tts-preview"
    static let gemini35Flash: Self = "gemini-3.5-flash"
    static let gemini35FlashLite: Self = "gemini-3.5-flash-lite"
    static let gemini36Flash: Self = "gemini-3.6-flash"
    static let gemini37Flash: Self = "gemini-3.7-flash"
    static let gemini38Flash: Self = "gemini-3.8-flash"
    static let gemini4Argon: Self = "gemini-4-argon"
    static let geminiNanoBanana21: Self = "gemini-nano-banana-2.1"
    static let geminiProLatest: Self = "gemini-pro-latest"
    static let geminiFlashLatest: Self = "gemini-flash-latest"
    static let geminiFlashLiteLatest: Self = "gemini-flash-lite-latest"
    static let deepResearchProPreview122025: Self = "deep-research-pro-preview-12-2025"
    static let deepResearchMaxPreview042026: Self = "deep-research-max-preview-04-2026"
    static let deepResearchPreview042026: Self = "deep-research-preview-04-2026"
    static let nanoBananaProPreview: Self = "nano-banana-pro-preview"
    static let aqa: Self = "aqa"
    static let geminiRoboticsER15Preview: Self = "gemini-robotics-er-1.5-preview"
    static let gemma31bIt: Self = "gemma-3-1b-it"
    static let gemma34bIt: Self = "gemma-3-4b-it"
    static let gemma3nE4bIt: Self = "gemma-3n-e4b-it"
    static let gemma3nE2bIt: Self = "gemma-3n-e2b-it"
    static let gemma312bIt: Self = "gemma-3-12b-it"
    static let gemma327bIt: Self = "gemma-3-27b-it"
}
public extension GoogleEmbeddingModelId {
    static let geminiEmbedding001: Self = "gemini-embedding-001"
    static let geminiEmbedding2: Self = "gemini-embedding-2"
    static let geminiEmbedding2Preview: Self = "gemini-embedding-2-preview"
}
public extension GoogleImageModelId {
    static let gemini25FlashImage: Self = "gemini-2.5-flash-image"
    static let gemini3ProImagePreview: Self = "gemini-3-pro-image-preview"
    static let gemini31FlashImagePreview: Self = "gemini-3.1-flash-image-preview"
    static let geminiNanoBanana21: Self = "gemini-nano-banana-2.1"
}
public extension GoogleVideoModelId {
    static let veo31FastGeneratePreview: Self = "veo-3.1-fast-generate-preview"
    static let veo31GeneratePreview: Self = "veo-3.1-generate-preview"
    static let veo31Generate: Self = "veo-3.1-generate"
    static let veo31LiteGeneratePreview: Self = "veo-3.1-lite-generate-preview"
    static let veo30Generate001: Self = "veo-3.0-generate-001"
    static let veo30FastGenerate001: Self = "veo-3.0-fast-generate-001"
    static let veo20Generate001: Self = "veo-2.0-generate-001"
}
