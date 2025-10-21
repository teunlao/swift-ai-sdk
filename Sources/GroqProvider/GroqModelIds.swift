import Foundation

public struct GroqChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known model identifiers (mirrors packages/groq/src/groq-chat-options.ts)

public extension GroqChatModelId {
    /// Production models — https://console.groq.com/docs/models
    static let gemma2_9b_it: Self = "gemma2-9b-it"
    static let llama31_8b_instant: Self = "llama-3.1-8b-instant"
    static let llama33_70b_versatile: Self = "llama-3.3-70b-versatile"
    static let llamaGuard4_12b: Self = "meta-llama/llama-guard-4-12b"
    static let gptOss120b: Self = "openai/gpt-oss-120b"
    static let gptOss20b: Self = "openai/gpt-oss-20b"

    /// Preview models (selection)
    static let deepseekR1DistillLlama70b: Self = "deepseek-r1-distill-llama-70b"
    static let llama4Maverick17b128eInstruct: Self = "meta-llama/llama-4-maverick-17b-128e-instruct"
    static let llama4Scout17b16eInstruct: Self = "meta-llama/llama-4-scout-17b-16e-instruct"
    static let llamaPromptGuard2_22m: Self = "meta-llama/llama-prompt-guard-2-22m"
    static let llamaPromptGuard2_86m: Self = "meta-llama/llama-prompt-guard-2-86m"
    static let moonshotKimiK2Instruct: Self = "moonshotai/kimi-k2-instruct"
    static let qwen3_32b: Self = "qwen/qwen3-32b"
    static let llamaGuard3_8b: Self = "llama-guard-3-8b"
    static let llama3_70b_8192: Self = "llama3-70b-8192"
    static let llama3_8b_8192: Self = "llama3-8b-8192"
    static let mixtral8x7b_32768: Self = "mixtral-8x7b-32768"
    static let qwenQwq32b: Self = "qwen-qwq-32b"
    static let qwen2_5_32b: Self = "qwen-2.5-32b"
    static let deepseekR1DistillQwen32b: Self = "deepseek-r1-distill-qwen-32b"
}

public struct GroqTranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension GroqTranscriptionModelId {
    static let whisperLargeV3Turbo: Self = "whisper-large-v3-turbo"
    static let distilWhisperLargeV3En: Self = "distil-whisper-large-v3-en"
    static let whisperLargeV3: Self = "whisper-large-v3"
}
