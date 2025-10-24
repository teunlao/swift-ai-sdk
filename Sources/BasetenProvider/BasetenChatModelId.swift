import Foundation

/// Baseten chat model identifiers.
/// Mirrors `packages/baseten/src/baseten-chat-options.ts`.
public struct BasetenChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension BasetenChatModelId {
    /// Supported models via Baseten Model APIs.
    static let deepseekR1_0528: Self = "deepseek-ai/DeepSeek-R1-0528"
    static let deepseekV3_0324: Self = "deepseek-ai/DeepSeek-V3-0324"
    static let deepseekV3_1: Self = "deepseek-ai/DeepSeek-V3.1"
    static let kimiK2Instruct0905: Self = "moonshotai/Kimi-K2-Instruct-0905"
    static let qwen3_235bA22bInstruct: Self = "Qwen/Qwen3-235B-A22B-Instruct-2507"
    static let qwen3Coder480bA35bInstruct: Self = "Qwen/Qwen3-Coder-480B-A35B-Instruct"
    static let openaiGptOss120b: Self = "openai/gpt-oss-120b"
    static let glm46: Self = "zai-org/GLM-4.6"
}
