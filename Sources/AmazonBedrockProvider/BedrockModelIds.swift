import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-chat-options.ts
// Ported from packages/amazon-bedrock/src/bedrock-embedding-options.ts
// Ported from packages/amazon-bedrock/src/bedrock-image-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct BedrockChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct BedrockEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct BedrockImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known Model Identifiers

public extension BedrockChatModelId {
    static let amazonTitanTG1Large: Self = "amazon.titan-tg1-large"
    static let amazonTitanTextExpressV1: Self = "amazon.titan-text-express-v1"
    static let anthropicClaudeV2: Self = "anthropic.claude-v2"
    static let anthropicClaudeV21: Self = "anthropic.claude-v2:1"
    static let anthropicClaudeInstantV1: Self = "anthropic.claude-instant-v1"
    static let anthropicClaudeHaiku45_20251001: Self = "anthropic.claude-haiku-4-5-20251001-v1:0"
    static let anthropicClaudeSonnet4_20250514: Self = "anthropic.claude-sonnet-4-20250514-v1:0"
    static let anthropicClaudeSonnet45_20250929: Self = "anthropic.claude-sonnet-4-5-20250929-v1:0"
    static let anthropicClaudeOpus4_20250514: Self = "anthropic.claude-opus-4-20250514-v1:0"
    static let anthropicClaudeOpus41_20250805: Self = "anthropic.claude-opus-4-1-20250805-v1:0"
    static let anthropicClaude37Sonnet_20250219: Self = "anthropic.claude-3-7-sonnet-20250219-v1:0"
    static let anthropicClaude35Sonnet_20240620: Self = "anthropic.claude-3-5-sonnet-20240620-v1:0"
    static let anthropicClaude35Sonnet_20241022_V2: Self = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    static let anthropicClaude35Haiku_20241022: Self = "anthropic.claude-3-5-haiku-20241022-v1:0"
    static let anthropicClaude3Sonnet_20240229: Self = "anthropic.claude-3-sonnet-20240229-v1:0"
    static let anthropicClaude3Haiku_20240307: Self = "anthropic.claude-3-haiku-20240307-v1:0"
    static let anthropicClaude3Opus_20240229: Self = "anthropic.claude-3-opus-20240229-v1:0"
    static let cohereCommandTextV14: Self = "cohere.command-text-v14"
    static let cohereCommandLightTextV14: Self = "cohere.command-light-text-v14"
    static let cohereCommandRV1: Self = "cohere.command-r-v1:0"
    static let cohereCommandRPlusV1: Self = "cohere.command-r-plus-v1:0"
    static let metaLlama3_70bInstructV1: Self = "meta.llama3-70b-instruct-v1:0"
    static let metaLlama3_8bInstructV1: Self = "meta.llama3-8b-instruct-v1:0"
    static let metaLlama31_405bInstructV1: Self = "meta.llama3-1-405b-instruct-v1:0"
    static let metaLlama31_70bInstructV1: Self = "meta.llama3-1-70b-instruct-v1:0"
    static let metaLlama31_8bInstructV1: Self = "meta.llama3-1-8b-instruct-v1:0"
    static let metaLlama32_11bInstructV1: Self = "meta.llama3-2-11b-instruct-v1:0"
    static let metaLlama32_1bInstructV1: Self = "meta.llama3-2-1b-instruct-v1:0"
    static let metaLlama32_3bInstructV1: Self = "meta.llama3-2-3b-instruct-v1:0"
    static let metaLlama32_90bInstructV1: Self = "meta.llama3-2-90b-instruct-v1:0"
    static let mistral7bInstructV02: Self = "mistral.mistral-7b-instruct-v0:2"
    static let mistralMixtral8x7bInstructV01: Self = "mistral.mixtral-8x7b-instruct-v0:1"
    static let mistralLarge2402: Self = "mistral.mistral-large-2402-v1:0"
    static let mistralSmall2402: Self = "mistral.mistral-small-2402-v1:0"
    static let openAIGptOss120b: Self = "openai.gpt-oss-120b-1:0"
    static let openAIGptOss20b: Self = "openai.gpt-oss-20b-1:0"
    static let amazonTitanTextLiteV1: Self = "amazon.titan-text-lite-v1"
    static let usAmazonNovaPremier: Self = "us.amazon.nova-premier-v1:0"
    static let usAmazonNovaPro: Self = "us.amazon.nova-pro-v1:0"
    static let usAmazonNovaMicro: Self = "us.amazon.nova-micro-v1:0"
    static let usAmazonNovaLite: Self = "us.amazon.nova-lite-v1:0"
    static let usAnthropicClaude3Sonnet: Self = "us.anthropic.claude-3-sonnet-20240229-v1:0"
    static let usAnthropicClaude3Opus: Self = "us.anthropic.claude-3-opus-20240229-v1:0"
    static let usAnthropicClaude3Haiku: Self = "us.anthropic.claude-3-haiku-20240307-v1:0"
    static let usAnthropicClaude35Sonnet_20240620: Self = "us.anthropic.claude-3-5-sonnet-20240620-v1:0"
    static let usAnthropicClaude35Haiku_20241022: Self = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
    static let usAnthropicClaude35Sonnet_20241022_V2: Self = "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
    static let usAnthropicClaude37Sonnet_20250219: Self = "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
    static let usAnthropicClaudeSonnet4_20250514: Self = "us.anthropic.claude-sonnet-4-20250514-v1:0"
    static let usAnthropicClaudeSonnet45_20250929: Self = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    static let usAnthropicClaudeOpus4_20250514: Self = "us.anthropic.claude-opus-4-20250514-v1:0"
    static let usAnthropicClaudeOpus41_20250805: Self = "us.anthropic.claude-opus-4-1-20250805-v1:0"
    static let usMetaLlama32_11b: Self = "us.meta.llama3-2-11b-instruct-v1:0"
    static let usMetaLlama32_3b: Self = "us.meta.llama3-2-3b-instruct-v1:0"
    static let usMetaLlama32_90b: Self = "us.meta.llama3-2-90b-instruct-v1:0"
    static let usMetaLlama32_1b: Self = "us.meta.llama3-2-1b-instruct-v1:0"
    static let usMetaLlama31_8b: Self = "us.meta.llama3-1-8b-instruct-v1:0"
    static let usMetaLlama31_70b: Self = "us.meta.llama3-1-70b-instruct-v1:0"
    static let usMetaLlama33_70b: Self = "us.meta.llama3-3-70b-instruct-v1:0"
    static let usDeepseekR1: Self = "us.deepseek.r1-v1:0"
    static let usMistralPixtralLarge2502: Self = "us.mistral.pixtral-large-2502-v1:0"
    static let usMetaLlama4Scout17b: Self = "us.meta.llama4-scout-17b-instruct-v1:0"
    static let usMetaLlama4Maverick17b: Self = "us.meta.llama4-maverick-17b-instruct-v1:0"
}

public extension BedrockEmbeddingModelId {
    static let amazonTitanEmbedTextV1: Self = "amazon.titan-embed-text-v1"
    static let amazonTitanEmbedTextV2: Self = "amazon.titan-embed-text-v2:0"
    static let cohereEmbedEnglishV3: Self = "cohere.embed-english-v3"
    static let cohereEmbedMultilingualV3: Self = "cohere.embed-multilingual-v3"
}

public extension BedrockImageModelId {
    static let amazonNovaCanvasV1: Self = "amazon.nova-canvas-v1:0"
}
