import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-language-model-settings.ts
// Ported from packages/gateway/src/gateway-embedding-model-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GatewayModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension GatewayModelId {
    static let alibabaQwen314b: Self = "alibaba/qwen-3-14b"
    static let alibabaQwen3235b: Self = "alibaba/qwen-3-235b"
    static let alibabaQwen330b: Self = "alibaba/qwen-3-30b"
    static let alibabaQwen332b: Self = "alibaba/qwen-3-32b"
    static let alibabaQwen3Coder: Self = "alibaba/qwen3-coder"
    static let alibabaQwen3CoderPlus: Self = "alibaba/qwen3-coder-plus"
    static let alibabaQwen3Max: Self = "alibaba/qwen3-max"
    static let alibabaQwen3MaxPreview: Self = "alibaba/qwen3-max-preview"
    static let alibabaQwen3Next80bA3bInstruct: Self = "alibaba/qwen3-next-80b-a3b-instruct"
    static let alibabaQwen3Next80bA3bThinking: Self = "alibaba/qwen3-next-80b-a3b-thinking"
    static let alibabaQwen3VlInstruct: Self = "alibaba/qwen3-vl-instruct"
    static let alibabaQwen3VlThinking: Self = "alibaba/qwen3-vl-thinking"
    static let amazonNovaLite: Self = "amazon/nova-lite"
    static let amazonNovaMicro: Self = "amazon/nova-micro"
    static let amazonNovaPro: Self = "amazon/nova-pro"
    static let anthropicClaude3Haiku: Self = "anthropic/claude-3-haiku"
    static let anthropicClaude3Opus: Self = "anthropic/claude-3-opus"
    static let anthropicClaude35Haiku: Self = "anthropic/claude-3.5-haiku"
    static let anthropicClaude35Sonnet: Self = "anthropic/claude-3.5-sonnet"
    static let anthropicClaude37Sonnet: Self = "anthropic/claude-3.7-sonnet"
    static let anthropicClaudeOpus4: Self = "anthropic/claude-opus-4"
    static let anthropicClaudeOpus41: Self = "anthropic/claude-opus-4.1"
    static let anthropicClaudeSonnet4: Self = "anthropic/claude-sonnet-4"
    static let anthropicClaudeSonnet45: Self = "anthropic/claude-sonnet-4.5"
    static let anthropicClaudeHaiku45: Self = "anthropic/claude-haiku-4.5"
    static let cohereCommandA: Self = "cohere/command-a"
    static let cohereCommandR: Self = "cohere/command-r"
    static let cohereCommandRPlus: Self = "cohere/command-r-plus"
    static let deepseekR1: Self = "deepseek/deepseek-r1"
    static let deepseekR1DistillLlama70b: Self = "deepseek/deepseek-r1-distill-llama-70b"
    static let deepseekV3: Self = "deepseek/deepseek-v3"
    static let deepseekV31: Self = "deepseek/deepseek-v3.1"
    static let deepseekV31Base: Self = "deepseek/deepseek-v3.1-base"
    static let deepseekV31Terminus: Self = "deepseek/deepseek-v3.1-terminus"
    static let deepseekV32Exp: Self = "deepseek/deepseek-v3.2-exp"
    static let deepseekV32ExpThinking: Self = "deepseek/deepseek-v3.2-exp-thinking"
    static let googleGemini20Flash: Self = "google/gemini-2.0-flash"
    static let googleGemini20FlashLite: Self = "google/gemini-2.0-flash-lite"
    static let googleGemini25Flash: Self = "google/gemini-2.5-flash"
    static let googleGemini25FlashImagePreview: Self = "google/gemini-2.5-flash-image-preview"
    static let googleGemini25FlashPreview092025: Self = "google/gemini-2.5-flash-preview-09-2025"
    static let googleGemini25FlashLite: Self = "google/gemini-2.5-flash-lite"
    static let googleGemini25FlashLitePreview092025: Self = "google/gemini-2.5-flash-lite-preview-09-2025"
    static let googleGemini25Pro: Self = "google/gemini-2.5-pro"
    static let googleGemma29b: Self = "google/gemma-2-9b"
    static let inceptionMercuryCoderSmall: Self = "inception/mercury-coder-small"
    static let meituanLongcatFlashChat: Self = "meituan/longcat-flash-chat"
    static let meituanLongcatFlashThinking: Self = "meituan/longcat-flash-thinking"
    static let metaLlama370b: Self = "meta/llama-3-70b"
    static let metaLlama38b: Self = "meta/llama-3-8b"
    static let metaLlama31_70b: Self = "meta/llama-3.1-70b"
    static let metaLlama31_8b: Self = "meta/llama-3.1-8b"
    static let metaLlama32_11b: Self = "meta/llama-3.2-11b"
    static let metaLlama32_1b: Self = "meta/llama-3.2-1b"
    static let metaLlama32_3b: Self = "meta/llama-3.2-3b"
    static let metaLlama32_90b: Self = "meta/llama-3.2-90b"
    static let metaLlama33_70b: Self = "meta/llama-3.3-70b"
    static let metaLlama4Maverick: Self = "meta/llama-4-maverick"
    static let metaLlama4Scout: Self = "meta/llama-4-scout"
    static let mistralCodestral: Self = "mistral/codestral"
    static let mistralDevstralSmall: Self = "mistral/devstral-small"
    static let mistralMagistralMedium: Self = "mistral/magistral-medium"
    static let mistralMagistralSmall: Self = "mistral/magistral-small"
    static let mistralMinistral3b: Self = "mistral/ministral-3b"
    static let mistralMinistral8b: Self = "mistral/ministral-8b"
    static let mistralMistralLarge: Self = "mistral/mistral-large"
    static let mistralMistralMedium: Self = "mistral/mistral-medium"
    static let mistralMistralSmall: Self = "mistral/mistral-small"
    static let mistralMixtral8x22bInstruct: Self = "mistral/mixtral-8x22b-instruct"
    static let mistralPixtral12b: Self = "mistral/pixtral-12b"
    static let mistralPixtralLarge: Self = "mistral/pixtral-large"
    static let moonshotaiKimiK2: Self = "moonshotai/kimi-k2"
    static let moonshotaiKimiK20905: Self = "moonshotai/kimi-k2-0905"
    static let moonshotaiKimiK2Turbo: Self = "moonshotai/kimi-k2-turbo"
    static let morphMorphV3Fast: Self = "morph/morph-v3-fast"
    static let morphMorphV3Large: Self = "morph/morph-v3-large"
    static let openaiGPT35Turbo: Self = "openai/gpt-3.5-turbo"
    static let openaiGPT35TurboInstruct: Self = "openai/gpt-3.5-turbo-instruct"
    static let openaiGPT4Turbo: Self = "openai/gpt-4-turbo"
    static let openaiGPT41: Self = "openai/gpt-4.1"
    static let openaiGPT41Mini: Self = "openai/gpt-4.1-mini"
    static let openaiGPT41Nano: Self = "openai/gpt-4.1-nano"
    static let openaiGPT40: Self = "openai/gpt-4o"
    static let openaiGPT40Mini: Self = "openai/gpt-4o-mini"
    static let openaiGPT5: Self = "openai/gpt-5"
    static let openaiGPT5Codex: Self = "openai/gpt-5-codex"
    static let openaiGPT5Mini: Self = "openai/gpt-5-mini"
    static let openaiGPT5Nano: Self = "openai/gpt-5-nano"
    static let openaiGPT5Pro: Self = "openai/gpt-5-pro"
    static let openaiGPTOss120b: Self = "openai/gpt-oss-120b"
    static let openaiGPTOss20b: Self = "openai/gpt-oss-20b"
    static let openaiO1: Self = "openai/o1"
    static let openaiO3: Self = "openai/o3"
    static let openaiO3Mini: Self = "openai/o3-mini"
    static let openaiO4Mini: Self = "openai/o4-mini"
    static let perplexitySonar: Self = "perplexity/sonar"
    static let perplexitySonarPro: Self = "perplexity/sonar-pro"
    static let perplexitySonarReasoning: Self = "perplexity/sonar-reasoning"
    static let perplexitySonarReasoningPro: Self = "perplexity/sonar-reasoning-pro"
    static let stealthSonomaDuskAlpha: Self = "stealth/sonoma-dusk-alpha"
    static let stealthSonomaSkyAlpha: Self = "stealth/sonoma-sky-alpha"
    static let vercelV010Md: Self = "vercel/v0-1.0-md"
    static let vercelV015Md: Self = "vercel/v0-1.5-md"
    static let xaiGrok2: Self = "xai/grok-2"
    static let xaiGrok2Vision: Self = "xai/grok-2-vision"
    static let xaiGrok3: Self = "xai/grok-3"
    static let xaiGrok3Fast: Self = "xai/grok-3-fast"
    static let xaiGrok3Mini: Self = "xai/grok-3-mini"
    static let xaiGrok3MiniFast: Self = "xai/grok-3-mini-fast"
    static let xaiGrok4: Self = "xai/grok-4"
    static let xaiGrokCodeFast1: Self = "xai/grok-code-fast-1"
    static let xaiGrok4FastNonReasoning: Self = "xai/grok-4-fast-non-reasoning"
    static let xaiGrok4FastReasoning: Self = "xai/grok-4-fast-reasoning"
    static let zaiGlm45: Self = "zai/glm-4.5"
    static let zaiGlm45Air: Self = "zai/glm-4.5-air"
    static let zaiGlm45v: Self = "zai/glm-4.5v"
    static let zaiGlm46: Self = "zai/glm-4.6"
}

public struct GatewayEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension GatewayEmbeddingModelId {
    static let amazonTitanEmbedTextV2: Self = "amazon/titan-embed-text-v2"
    static let cohereEmbedV40: Self = "cohere/embed-v4.0"
    static let googleGeminiEmbedding001: Self = "google/gemini-embedding-001"
    static let googleTextEmbedding005: Self = "google/text-embedding-005"
    static let googleTextMultilingualEmbedding002: Self = "google/text-multilingual-embedding-002"
    static let mistralCodestralEmbed: Self = "mistral/codestral-embed"
    static let mistralMistralEmbed: Self = "mistral/mistral-embed"
    static let openaiTextEmbedding3Large: Self = "openai/text-embedding-3-large"
    static let openaiTextEmbedding3Small: Self = "openai/text-embedding-3-small"
    static let openaiTextEmbeddingAda002: Self = "openai/text-embedding-ada-002"
    static let voyageVoyage3Large: Self = "voyage/voyage-3-large"
    static let voyageVoyage35: Self = "voyage/voyage-3.5"
    static let voyageVoyage35Lite: Self = "voyage/voyage-3.5-lite"
    static let voyageVoyageCode3: Self = "voyage/voyage-code-3"
    static let voyageVoyageFinance2: Self = "voyage/voyage-finance-2"
    static let voyageVoyageLaw2: Self = "voyage/voyage-law-2"
    static let voyageVoyageCode2: Self = "voyage/voyage-code-2"
}
