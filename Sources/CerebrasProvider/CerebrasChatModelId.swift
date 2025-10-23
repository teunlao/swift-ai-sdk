import Foundation

/// Represents Cerebras chat model identifiers.
/// Mirrors `packages/cerebras/src/cerebras-chat-options.ts`.
public struct CerebrasChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension CerebrasChatModelId {
    /// Known model identifiers documented at https://inference-docs.cerebras.ai/introduction
    static let llama33_70b: Self = "llama-3.3-70b"
    static let llama31_8b: Self = "llama3.1-8b"
    static let gptOss120b: Self = "gpt-oss-120b"
    static let qwen3_235bA22bInstruct2507: Self = "qwen-3-235b-a22b-instruct-2507"
    static let qwen3_235bA22bThinking2507: Self = "qwen-3-235b-a22b-thinking-2507"
    static let qwen3_32b: Self = "qwen-3-32b"
    static let qwen3Coder480b: Self = "qwen-3-coder-480b"
}
