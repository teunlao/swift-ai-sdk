import Foundation

// Generated from packages/gateway/src/*-model-settings.ts at 8a5233b15b1e69573d63faee6cd0014559252ee4.

public struct GatewayModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayModelId {
    static let alibabaQwen314b: Self = "alibaba/qwen-3-14b"
    static let alibabaQwen3235b: Self = "alibaba/qwen-3-235b"
    static let alibabaQwen330b: Self = "alibaba/qwen-3-30b"
    static let alibabaQwen332b: Self = "alibaba/qwen-3-32b"
    static let alibabaQwen3Coder: Self = "alibaba/qwen3-coder"
    static let alibabaQwen3Coder30bA3b: Self = "alibaba/qwen3-coder-30b-a3b"
    static let alibabaQwen3CoderNext: Self = "alibaba/qwen3-coder-next"
    static let alibabaQwen3MaxThinking: Self = "alibaba/qwen3-max-thinking"
    static let alibabaQwen3Next80bA3bInstruct: Self = "alibaba/qwen3-next-80b-a3b-instruct"
    static let alibabaQwen3Next80bA3bThinking: Self = "alibaba/qwen3-next-80b-a3b-thinking"
    static let alibabaQwen3VlInstruct: Self = "alibaba/qwen3-vl-instruct"
    static let alibabaQwen35Flash: Self = "alibaba/qwen3.5-flash"
    static let alibabaQwen35Plus: Self = "alibaba/qwen3.5-plus"
    static let alibabaQwen3627b: Self = "alibaba/qwen3.6-27b"
    static let alibabaQwen36Plus: Self = "alibaba/qwen3.6-plus"
    static let alibabaQwen37Flash: Self = "alibaba/qwen3.7-flash"
    static let alibabaQwen37Max: Self = "alibaba/qwen3.7-max"
    static let alibabaQwen37Plus: Self = "alibaba/qwen3.7-plus"
    static let alibabaQwen3824tA95b: Self = "alibaba/qwen3.8-2.4t-a95b"
    static let alibabaQwen3827b: Self = "alibaba/qwen3.8-27b"
    static let alibabaQwen38Flash: Self = "alibaba/qwen3.8-flash"
    static let alibabaQwen38Max: Self = "alibaba/qwen3.8-max"
    static let alibabaQwen38Max0902: Self = "alibaba/qwen3.8-max-0902"
    static let alibabaQwen38MaxPrime: Self = "alibaba/qwen3.8-max-prime"
    static let alibabaQwen38OmniFlash: Self = "alibaba/qwen3.8-omni-flash"
    static let amazonNova2Lite: Self = "amazon/nova-2-lite"
    static let amazonNovaLite: Self = "amazon/nova-lite"
    static let amazonNovaMicro: Self = "amazon/nova-micro"
    static let amazonNovaPro: Self = "amazon/nova-pro"
    static let anthropicClaudeFable5: Self = "anthropic/claude-fable-5"
    static let anthropicClaudeFable5Batch: Self = "anthropic/claude-fable-5-batch"
    static let anthropicClaudeFable51: Self = "anthropic/claude-fable-5.1"
    static let anthropicClaudeFable51Batch: Self = "anthropic/claude-fable-5.1-batch"
    static let anthropicClaudeHaiku45: Self = "anthropic/claude-haiku-4.5"
    static let anthropicClaudeHaiku45Batch: Self = "anthropic/claude-haiku-4.5-batch"
    static let anthropicClaudeHaiku55: Self = "anthropic/claude-haiku-5.5"
    static let anthropicClaudeHaiku55Batch: Self = "anthropic/claude-haiku-5.5-batch"
    static let anthropicClaudeOpus45: Self = "anthropic/claude-opus-4.5"
    static let anthropicClaudeOpus45Batch: Self = "anthropic/claude-opus-4.5-batch"
    static let anthropicClaudeOpus46: Self = "anthropic/claude-opus-4.6"
    static let anthropicClaudeOpus46Batch: Self = "anthropic/claude-opus-4.6-batch"
    static let anthropicClaudeOpus47: Self = "anthropic/claude-opus-4.7"
    static let anthropicClaudeOpus47Batch: Self = "anthropic/claude-opus-4.7-batch"
    static let anthropicClaudeOpus48: Self = "anthropic/claude-opus-4.8"
    static let anthropicClaudeOpus48Batch: Self = "anthropic/claude-opus-4.8-batch"
    static let anthropicClaudeOpus48Fast: Self = "anthropic/claude-opus-4.8-fast"
    static let anthropicClaudeOpus5: Self = "anthropic/claude-opus-5"
    static let anthropicClaudeOpus5Batch: Self = "anthropic/claude-opus-5-batch"
    static let anthropicClaudeOpus5Fast: Self = "anthropic/claude-opus-5-fast"
    static let anthropicClaudeOpus55: Self = "anthropic/claude-opus-5.5"
    static let anthropicClaudeOpus55Batch: Self = "anthropic/claude-opus-5.5-batch"
    static let anthropicClaudeOpus55Fast: Self = "anthropic/claude-opus-5.5-fast"
    static let anthropicClaudeSonnet4: Self = "anthropic/claude-sonnet-4"
    static let anthropicClaudeSonnet45: Self = "anthropic/claude-sonnet-4.5"
    static let anthropicClaudeSonnet45Batch: Self = "anthropic/claude-sonnet-4.5-batch"
    static let anthropicClaudeSonnet46: Self = "anthropic/claude-sonnet-4.6"
    static let anthropicClaudeSonnet46Batch: Self = "anthropic/claude-sonnet-4.6-batch"
    static let anthropicClaudeSonnet5: Self = "anthropic/claude-sonnet-5"
    static let anthropicClaudeSonnet5Batch: Self = "anthropic/claude-sonnet-5-batch"
    static let anthropicClaudeSonnet55: Self = "anthropic/claude-sonnet-5.5"
    static let anthropicClaudeSonnet55Batch: Self = "anthropic/claude-sonnet-5.5-batch"
    static let arceeAiTrinityLargeThinking: Self = "arcee-ai/trinity-large-thinking"
    static let bytedanceSeed16: Self = "bytedance/seed-1.6"
    static let bytedanceSeed18: Self = "bytedance/seed-1.8"
    static let bytedanceSeed21Turbo: Self = "bytedance/seed-2.1-turbo"
    static let callstackApex: Self = "callstack/apex"
    static let cohereCommandA: Self = "cohere/command-a"
    static let deepseekR1: Self = "deepseek/deepseek-r1"
    static let deepseekV31: Self = "deepseek/deepseek-v3.1"
    static let deepseekDeepseekV32: Self = "deepseek/deepseek-v3.2"
    static let deepseekDeepseekV32Thinking: Self = "deepseek/deepseek-v3.2-thinking"
    static let deepseekDeepseekV4Flash: Self = "deepseek/deepseek-v4-flash"
    static let deepseekDeepseekV4Flash0731: Self = "deepseek/deepseek-v4-flash-0731"
    static let deepseekDeepseekV4FlashVisionExp: Self = "deepseek/deepseek-v4-flash-vision-exp"
    static let deepseekDeepseekV4Pro: Self = "deepseek/deepseek-v4-pro"
    static let deepseekDeepseekV4Pro0813: Self = "deepseek/deepseek-v4-pro-0813"
    static let deepseekDeepseekV41Flash: Self = "deepseek/deepseek-v4.1-flash"
    static let deepseekDeepseekV41FlashFast: Self = "deepseek/deepseek-v4.1-flash-fast"
    static let fireworksEmber1: Self = "fireworks/ember-1"
    static let googleGemini25Flash: Self = "google/gemini-2.5-flash"
    static let googleGemini25FlashBatch: Self = "google/gemini-2.5-flash-batch"
    static let googleGemini25FlashImage: Self = "google/gemini-2.5-flash-image"
    static let googleGemini25FlashLite: Self = "google/gemini-2.5-flash-lite"
    static let googleGemini25FlashLiteBatch: Self = "google/gemini-2.5-flash-lite-batch"
    static let googleGemini25Pro: Self = "google/gemini-2.5-pro"
    static let googleGemini25ProBatch: Self = "google/gemini-2.5-pro-batch"
    static let googleGemini3Flash: Self = "google/gemini-3-flash"
    static let googleGemini3FlashBatch: Self = "google/gemini-3-flash-batch"
    static let googleGemini3ProImage: Self = "google/gemini-3-pro-image"
    static let googleGemini31FlashImage: Self = "google/gemini-3.1-flash-image"
    static let googleGemini31FlashImagePreview: Self = "google/gemini-3.1-flash-image-preview"
    static let googleGemini31FlashLite: Self = "google/gemini-3.1-flash-lite"
    static let googleGemini31FlashLiteBatch: Self = "google/gemini-3.1-flash-lite-batch"
    static let googleGemini31FlashLiteImage: Self = "google/gemini-3.1-flash-lite-image"
    static let googleGemini31ProPreview: Self = "google/gemini-3.1-pro-preview"
    static let googleGemini31ProPreviewBatch: Self = "google/gemini-3.1-pro-preview-batch"
    static let googleGemini35Flash: Self = "google/gemini-3.5-flash"
    static let googleGemini35FlashBatch: Self = "google/gemini-3.5-flash-batch"
    static let googleGemini35FlashLite: Self = "google/gemini-3.5-flash-lite"
    static let googleGemini35FlashLiteBatch: Self = "google/gemini-3.5-flash-lite-batch"
    static let googleGemini36Flash: Self = "google/gemini-3.6-flash"
    static let googleGemini36FlashBatch: Self = "google/gemini-3.6-flash-batch"
    static let googleGemini37Flash: Self = "google/gemini-3.7-flash"
    static let googleGemini37FlashBatch: Self = "google/gemini-3.7-flash-batch"
    static let googleGemini38Flash: Self = "google/gemini-3.8-flash"
    static let googleGemini4Argon: Self = "google/gemini-4-argon"
    static let googleGeminiNanoBanana21: Self = "google/gemini-nano-banana-2.1"
    static let googleGeminiOmniFlashPreview: Self = "google/gemini-omni-flash-preview"
    static let googleGemma426bA4bIt: Self = "google/gemma-4-26b-a4b-it"
    static let googleGemma431bIt: Self = "google/gemma-4-31b-it"
    static let inceptionMercury2: Self = "inception/mercury-2"
    static let inceptionMercury25: Self = "inception/mercury-2.5"
    static let inceptionMercuryCoderSmall: Self = "inception/mercury-coder-small"
    static let inclusionaiLing30Flash: Self = "inclusionai/ling-3.0-flash"
    static let inclusionaiLing30FlashFin: Self = "inclusionai/ling-3.0-flash-fin"
    static let inclusionaiLing30FlashSante: Self = "inclusionai/ling-3.0-flash-sante"
    static let inclusionaiLing30FlashVl: Self = "inclusionai/ling-3.0-flash-vl"
    static let inclusionaiLing31Flash: Self = "inclusionai/ling-3.1-flash"
    static let inferenceNetSchematronV2Small: Self = "inference-net/schematron-v2-small"
    static let inferenceNetSchematronV2Turbo: Self = "inference-net/schematron-v2-turbo"
    static let interfazeInterfazeBeta: Self = "interfaze/interfaze-beta"
    static let liquidLfm2524bA2b: Self = "liquid/lfm2.5-24b-a2b"
    static let meituanLongcat25Preview: Self = "meituan/longcat-2.5-preview"
    static let metaLlama31_70b: Self = "meta/llama-3.1-70b"
    static let metaLlama31_8b: Self = "meta/llama-3.1-8b"
    static let metaLlama33_70b: Self = "meta/llama-3.3-70b"
    static let metaLlama4Maverick: Self = "meta/llama-4-maverick"
    static let metaLlama4Scout: Self = "meta/llama-4-scout"
    static let metaMuseGlimmer30b: Self = "meta/muse-glimmer-30b"
    static let metaMuseSpark11: Self = "meta/muse-spark-1.1"
    static let metaMuseSpark12: Self = "meta/muse-spark-1.2"
    static let metaMuseSpark12Contributor: Self = "meta/muse-spark-1.2-contributor"
    static let metaMuseSpark13: Self = "meta/muse-spark-1.3"
    static let metaMuseSpark13Contributor: Self = "meta/muse-spark-1.3-contributor"
    static let metaMuseWonder10: Self = "meta/muse-wonder-1.0"
    static let minimaxMinimaxM2: Self = "minimax/minimax-m2"
    static let minimaxMinimaxM21: Self = "minimax/minimax-m2.1"
    static let minimaxMinimaxM21Lightning: Self = "minimax/minimax-m2.1-lightning"
    static let minimaxMinimaxM25: Self = "minimax/minimax-m2.5"
    static let minimaxMinimaxM25Highspeed: Self = "minimax/minimax-m2.5-highspeed"
    static let minimaxMinimaxM27: Self = "minimax/minimax-m2.7"
    static let minimaxMinimaxM27Highspeed: Self = "minimax/minimax-m2.7-highspeed"
    static let minimaxMinimaxM3: Self = "minimax/minimax-m3"
    static let mistralCodestral: Self = "mistral/codestral"
    static let mistralMinistral14b: Self = "mistral/ministral-14b"
    static let mistralMinistral3b: Self = "mistral/ministral-3b"
    static let mistralMinistral8b: Self = "mistral/ministral-8b"
    static let mistralMistralLarge3: Self = "mistral/mistral-large-3"
    static let mistralMistralLarge4: Self = "mistral/mistral-large-4"
    static let mistralMistralMedium35: Self = "mistral/mistral-medium-3.5"
    static let mistralMistralNemo: Self = "mistral/mistral-nemo"
    static let mistralMistralSmall: Self = "mistral/mistral-small"
    static let mixedbreadToast1: Self = "mixedbread/toast-1"
    static let moonshotaiKimiK2: Self = "moonshotai/kimi-k2"
    static let moonshotaiKimiK25: Self = "moonshotai/kimi-k2.5"
    static let moonshotaiKimiK26: Self = "moonshotai/kimi-k2.6"
    static let moonshotaiKimiK27Code: Self = "moonshotai/kimi-k2.7-code"
    static let moonshotaiKimiK27CodeHighspeed: Self = "moonshotai/kimi-k2.7-code-highspeed"
    static let moonshotaiKimiK3: Self = "moonshotai/kimi-k3"
    static let moonshotaiKimiK3Fast: Self = "moonshotai/kimi-k3-fast"
    static let morphMorphV3Fast: Self = "morph/morph-v3-fast"
    static let morphMorphV3Large: Self = "morph/morph-v3-large"
    static let nvidiaNemotron3Nano30bA3b: Self = "nvidia/nemotron-3-nano-30b-a3b"
    static let nvidiaNemotron3Super120bA12b: Self = "nvidia/nemotron-3-super-120b-a12b"
    static let nvidiaNemotron3Ultra550bA55b: Self = "nvidia/nemotron-3-ultra-550b-a55b"
    static let nvidiaNemotron35Lightning: Self = "nvidia/nemotron-3.5-lightning"
    static let nvidiaNemotron35LightningFree: Self = "nvidia/nemotron-3.5-lightning-free"
    static let nvidiaNemotronNano12bV2Vl: Self = "nvidia/nemotron-nano-12b-v2-vl"
    static let nvidiaNemotronNano9bV2: Self = "nvidia/nemotron-nano-9b-v2"
    static let openaiGPT35Turbo: Self = "openai/gpt-3.5-turbo"
    static let openaiGPT4Turbo: Self = "openai/gpt-4-turbo"
    static let openaiGPT41: Self = "openai/gpt-4.1"
    static let openaiGPT41Batch: Self = "openai/gpt-4.1-batch"
    static let openaiGPT41Fast: Self = "openai/gpt-4.1-fast"
    static let openaiGPT41Mini: Self = "openai/gpt-4.1-mini"
    static let openaiGPT41MiniBatch: Self = "openai/gpt-4.1-mini-batch"
    static let openaiGPT41MiniFast: Self = "openai/gpt-4.1-mini-fast"
    static let openaiGPT41Nano: Self = "openai/gpt-4.1-nano"
    static let openaiGPT41NanoBatch: Self = "openai/gpt-4.1-nano-batch"
    static let openaiGPT41NanoFast: Self = "openai/gpt-4.1-nano-fast"
    static let openaiGPT40: Self = "openai/gpt-4o"
    static let openaiGPT4oBatch: Self = "openai/gpt-4o-batch"
    static let openaiGPT4oFast: Self = "openai/gpt-4o-fast"
    static let openaiGPT40Mini: Self = "openai/gpt-4o-mini"
    static let openaiGPT4oMiniBatch: Self = "openai/gpt-4o-mini-batch"
    static let openaiGPT4oMiniFast: Self = "openai/gpt-4o-mini-fast"
    static let openaiGPT5: Self = "openai/gpt-5"
    static let openaiGPT5Batch: Self = "openai/gpt-5-batch"
    static let openaiGPT5Codex: Self = "openai/gpt-5-codex"
    static let openaiGPT5Fast: Self = "openai/gpt-5-fast"
    static let openaiGPT5Mini: Self = "openai/gpt-5-mini"
    static let openaiGPT5MiniBatch: Self = "openai/gpt-5-mini-batch"
    static let openaiGPT5MiniFast: Self = "openai/gpt-5-mini-fast"
    static let openaiGPT5Nano: Self = "openai/gpt-5-nano"
    static let openaiGPT5NanoBatch: Self = "openai/gpt-5-nano-batch"
    static let openaiGPT5Pro: Self = "openai/gpt-5-pro"
    static let openaiGPT5ProBatch: Self = "openai/gpt-5-pro-batch"
    static let openaiGPT51Codex: Self = "openai/gpt-5.1-codex"
    static let openaiGPT51CodexMax: Self = "openai/gpt-5.1-codex-max"
    static let openaiGPT51CodexMini: Self = "openai/gpt-5.1-codex-mini"
    static let openaiGPT51Thinking: Self = "openai/gpt-5.1-thinking"
    static let openaiGPT51ThinkingFast: Self = "openai/gpt-5.1-thinking-fast"
    static let openaiGPT52: Self = "openai/gpt-5.2"
    static let openaiGPT52Batch: Self = "openai/gpt-5.2-batch"
    static let openaiGPT52Codex: Self = "openai/gpt-5.2-codex"
    static let openaiGPT52Fast: Self = "openai/gpt-5.2-fast"
    static let openaiGPT52Pro: Self = "openai/gpt-5.2-pro"
    static let openaiGPT53Codex: Self = "openai/gpt-5.3-codex"
    static let openaiGPT53CodexFast: Self = "openai/gpt-5.3-codex-fast"
    static let openaiGPT54: Self = "openai/gpt-5.4"
    static let openaiGPT54Batch: Self = "openai/gpt-5.4-batch"
    static let openaiGPT54Fast: Self = "openai/gpt-5.4-fast"
    static let openaiGPT54Mini: Self = "openai/gpt-5.4-mini"
    static let openaiGPT54MiniBatch: Self = "openai/gpt-5.4-mini-batch"
    static let openaiGPT54MiniFast: Self = "openai/gpt-5.4-mini-fast"
    static let openaiGPT54Nano: Self = "openai/gpt-5.4-nano"
    static let openaiGPT54NanoBatch: Self = "openai/gpt-5.4-nano-batch"
    static let openaiGPT54Pro: Self = "openai/gpt-5.4-pro"
    static let openaiGPT55: Self = "openai/gpt-5.5"
    static let openaiGPT55Batch: Self = "openai/gpt-5.5-batch"
    static let openaiGPT55Fast: Self = "openai/gpt-5.5-fast"
    static let openaiGPT55Pro: Self = "openai/gpt-5.5-pro"
    static let openaiGPT55ProBatch: Self = "openai/gpt-5.5-pro-batch"
    static let openaiGPT56Luna: Self = "openai/gpt-5.6-luna"
    static let openaiGPT56LunaBatch: Self = "openai/gpt-5.6-luna-batch"
    static let openaiGPT56LunaFast: Self = "openai/gpt-5.6-luna-fast"
    static let openaiGPT56Sol: Self = "openai/gpt-5.6-sol"
    static let openaiGPT56SolBatch: Self = "openai/gpt-5.6-sol-batch"
    static let openaiGPT56SolFast: Self = "openai/gpt-5.6-sol-fast"
    static let openaiGPT56Terra: Self = "openai/gpt-5.6-terra"
    static let openaiGPT56TerraBatch: Self = "openai/gpt-5.6-terra-batch"
    static let openaiGPT56TerraFast: Self = "openai/gpt-5.6-terra-fast"
    static let openaiGPT6Astra: Self = "openai/gpt-6-astra"
    static let openaiGPT6AstraBatch: Self = "openai/gpt-6-astra-batch"
    static let openaiGPT6AstraFast: Self = "openai/gpt-6-astra-fast"
    static let openaiGPT6Luna: Self = "openai/gpt-6-luna"
    static let openaiGPT6LunaBatch: Self = "openai/gpt-6-luna-batch"
    static let openaiGPT6LunaFast: Self = "openai/gpt-6-luna-fast"
    static let openaiGPT6Sol: Self = "openai/gpt-6-sol"
    static let openaiGPT6SolBatch: Self = "openai/gpt-6-sol-batch"
    static let openaiGPT6SolFast: Self = "openai/gpt-6-sol-fast"
    static let openaiGPT61Sol: Self = "openai/gpt-6.1-sol"
    static let openaiGPT61SolBatch: Self = "openai/gpt-6.1-sol-batch"
    static let openaiGPT61SolFast: Self = "openai/gpt-6.1-sol-fast"
    static let openaiGPTOss120b: Self = "openai/gpt-oss-120b"
    static let openaiGPTOss20b: Self = "openai/gpt-oss-20b"
    static let openaiGPTOssSafeguard120b: Self = "openai/gpt-oss-safeguard-120b"
    static let openaiGPTOssSafeguard20b: Self = "openai/gpt-oss-safeguard-20b"
    static let openaiO1: Self = "openai/o1"
    static let openaiO3: Self = "openai/o3"
    static let openaiO3Fast: Self = "openai/o3-fast"
    static let openaiO3Mini: Self = "openai/o3-mini"
    static let openaiO3Pro: Self = "openai/o3-pro"
    static let openaiO4Mini: Self = "openai/o4-mini"
    static let openaiO4MiniFast: Self = "openai/o4-mini-fast"
    static let perplexitySonar: Self = "perplexity/sonar"
    static let poolsideLagunaS21: Self = "poolside/laguna-s-2.1"
    static let poolsideLagunaS21Free: Self = "poolside/laguna-s-2.1-free"
    static let quiveraiArrow2: Self = "quiverai/arrow-2"
    static let quiveraiArrow2Telos: Self = "quiverai/arrow-2-telos"
    static let sakanaFuguMax: Self = "sakana/fugu-max"
    static let sakanaFuguUltra: Self = "sakana/fugu-ultra"
    static let sakanaFuguUltraV2: Self = "sakana/fugu-ultra-v2"
    static let sakanaNamazu: Self = "sakana/namazu"
    static let spacexaiGrok41FastNonReasoning: Self = "spacexai/grok-4.1-fast-non-reasoning"
    static let spacexaiGrok41FastReasoning: Self = "spacexai/grok-4.1-fast-reasoning"
    static let spacexaiGrok420MultiAgent: Self = "spacexai/grok-4.20-multi-agent"
    static let spacexaiGrok420MultiAgentBatch: Self = "spacexai/grok-4.20-multi-agent-batch"
    static let spacexaiGrok420MultiAgentBeta: Self = "spacexai/grok-4.20-multi-agent-beta"
    static let spacexaiGrok420NonReasoning: Self = "spacexai/grok-4.20-non-reasoning"
    static let spacexaiGrok420NonReasoningBatch: Self = "spacexai/grok-4.20-non-reasoning-batch"
    static let spacexaiGrok420NonReasoningBeta: Self = "spacexai/grok-4.20-non-reasoning-beta"
    static let spacexaiGrok420Reasoning: Self = "spacexai/grok-4.20-reasoning"
    static let spacexaiGrok420ReasoningBatch: Self = "spacexai/grok-4.20-reasoning-batch"
    static let spacexaiGrok420ReasoningBeta: Self = "spacexai/grok-4.20-reasoning-beta"
    static let spacexaiGrok43: Self = "spacexai/grok-4.3"
    static let spacexaiGrok43Batch: Self = "spacexai/grok-4.3-batch"
    static let spacexaiGrok45: Self = "spacexai/grok-4.5"
    static let spacexaiGrok46: Self = "spacexai/grok-4.6"
    static let spacexaiGrok47: Self = "spacexai/grok-4.7"
    static let spacexaiGrokBuild01: Self = "spacexai/grok-build-0.1"
    static let stealthGlyphCluster: Self = "stealth/glyph-cluster"
    static let stepfunStep37Flash: Self = "stepfun/step-3.7-flash"
    static let stepfunStep5Preview: Self = "stepfun/step-5-preview"
    static let tencentHyMt2Lite: Self = "tencent/hy-mt2-lite"
    static let tencentHyMt2Plus: Self = "tencent/hy-mt2-plus"
    static let tencentHyMt2Pro: Self = "tencent/hy-mt2-pro"
    static let tencentHy3: Self = "tencent/hy3"
    static let tencentHy4Preview: Self = "tencent/hy4-preview"
    static let thinkingmachinesInkling: Self = "thinkingmachines/inkling"
    static let thinkingmachinesInklingSmall: Self = "thinkingmachines/inkling-small"
    static let xiaomiMimoV25: Self = "xiaomi/mimo-v2.5"
    static let xiaomiMimoV25Pro: Self = "xiaomi/mimo-v2.5-pro"
    static let xiaomiMimoV26Flash: Self = "xiaomi/mimo-v2.6-flash"
    static let xiaomiMimoV26Pro: Self = "xiaomi/mimo-v2.6-pro"
    static let xiaomiMimoV26ProUltraspeed: Self = "xiaomi/mimo-v2.6-pro-ultraspeed"
    static let zaiGlm45: Self = "zai/glm-4.5"
    static let zaiGlm45Air: Self = "zai/glm-4.5-air"
    static let zaiGlm45v: Self = "zai/glm-4.5v"
    static let zaiGlm46: Self = "zai/glm-4.6"
    static let zaiGlm47: Self = "zai/glm-4.7"
    static let zaiGlm47Flash: Self = "zai/glm-4.7-flash"
    static let zaiGlm47Flashx: Self = "zai/glm-4.7-flashx"
    static let zaiGlm5: Self = "zai/glm-5"
    static let zaiGlm5Turbo: Self = "zai/glm-5-turbo"
    static let zaiGlm51: Self = "zai/glm-5.1"
    static let zaiGlm52: Self = "zai/glm-5.2"
    static let zaiGlm52Fast: Self = "zai/glm-5.2-fast"
    static let zaiGlm53: Self = "zai/glm-5.3"
    static let zaiGlm53Fast: Self = "zai/glm-5.3-fast"
    static let zaiGlm53Flash: Self = "zai/glm-5.3-flash"
    static let zaiGlm53Flashx: Self = "zai/glm-5.3-flashx"
    static let zaiGlm5vTurbo: Self = "zai/glm-5v-turbo"
}

public struct GatewayEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayEmbeddingModelId {
    static let alibabaQwen3Embedding06b: Self = "alibaba/qwen3-embedding-0.6b"
    static let alibabaQwen3Embedding4b: Self = "alibaba/qwen3-embedding-4b"
    static let alibabaQwen3Embedding8b: Self = "alibaba/qwen3-embedding-8b"
    static let amazonTitanEmbedTextV2: Self = "amazon/titan-embed-text-v2"
    static let cohereEmbedV40: Self = "cohere/embed-v4.0"
    static let cohereEmbedV50Fast: Self = "cohere/embed-v5.0-fast"
    static let cohereEmbedV50Pro: Self = "cohere/embed-v5.0-pro"
    static let googleGeminiEmbedding001: Self = "google/gemini-embedding-001"
    static let googleGeminiEmbedding2: Self = "google/gemini-embedding-2"
    static let googleTextEmbedding005: Self = "google/text-embedding-005"
    static let googleTextMultilingualEmbedding002: Self = "google/text-multilingual-embedding-002"
    static let mistralCodestralEmbed: Self = "mistral/codestral-embed"
    static let mistralMistralEmbed: Self = "mistral/mistral-embed"
    static let openaiTextEmbedding3Large: Self = "openai/text-embedding-3-large"
    static let openaiTextEmbedding3Small: Self = "openai/text-embedding-3-small"
    static let openaiTextEmbeddingAda002: Self = "openai/text-embedding-ada-002"
    static let perplexityPplxEmbedV106b: Self = "perplexity/pplx-embed-v1-0.6b"
    static let perplexityPplxEmbedV14b: Self = "perplexity/pplx-embed-v1-4b"
    static let voyageVoyage3Large: Self = "voyage/voyage-3-large"
    static let voyageVoyage35: Self = "voyage/voyage-3.5"
    static let voyageVoyage35Lite: Self = "voyage/voyage-3.5-lite"
    static let voyageVoyage4: Self = "voyage/voyage-4"
    static let voyageVoyage4Large: Self = "voyage/voyage-4-large"
    static let voyageVoyage4Lite: Self = "voyage/voyage-4-lite"
    static let voyageVoyageCode2: Self = "voyage/voyage-code-2"
    static let voyageVoyageCode3: Self = "voyage/voyage-code-3"
    static let voyageVoyageFinance2: Self = "voyage/voyage-finance-2"
    static let voyageVoyageLaw2: Self = "voyage/voyage-law-2"
}

public struct GatewayImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayImageModelId {
    static let bflFlux2Flex: Self = "bfl/flux-2-flex"
    static let bflFlux2Klein4b: Self = "bfl/flux-2-klein-4b"
    static let bflFlux2Klein9b: Self = "bfl/flux-2-klein-9b"
    static let bflFlux2Max: Self = "bfl/flux-2-max"
    static let bflFlux2Pro: Self = "bfl/flux-2-pro"
    static let bflFlux3Image: Self = "bfl/flux-3-image"
    static let bflFluxKontextMax: Self = "bfl/flux-kontext-max"
    static let bflFluxKontextPro: Self = "bfl/flux-kontext-pro"
    static let bflFluxPro10Fill: Self = "bfl/flux-pro-1.0-fill"
    static let bflFluxPro11: Self = "bfl/flux-pro-1.1"
    static let bflFluxPro11Ultra: Self = "bfl/flux-pro-1.1-ultra"
    static let bytedanceSeedream40: Self = "bytedance/seedream-4.0"
    static let bytedanceSeedream45: Self = "bytedance/seedream-4.5"
    static let bytedanceSeedream50Lite: Self = "bytedance/seedream-5.0-lite"
    static let bytedanceSeedream50Pro: Self = "bytedance/seedream-5.0-pro"
    static let metaMuseImage10: Self = "meta/muse-image-1.0"
    static let microsoftMaiImage26: Self = "microsoft/mai-image-2.6"
    static let microsoftMaiImage26Flash: Self = "microsoft/mai-image-2.6-flash"
    static let openaiGPTImage1: Self = "openai/gpt-image-1"
    static let openaiGPTImage1Mini: Self = "openai/gpt-image-1-mini"
    static let openaiGPTImage15: Self = "openai/gpt-image-1.5"
    static let openaiGPTImage2: Self = "openai/gpt-image-2"
    static let openaiGPTImage25Flare: Self = "openai/gpt-image-2.5-flare"
    static let openaiGPTImage25Sunburst: Self = "openai/gpt-image-2.5-sunburst"
    static let prodiaFluxFastSchnell: Self = "prodia/flux-fast-schnell"
    static let quiveraiArrow11: Self = "quiverai/arrow-1.1"
    static let recraftRecraftV2: Self = "recraft/recraft-v2"
    static let recraftRecraftV3: Self = "recraft/recraft-v3"
    static let recraftRecraftV4: Self = "recraft/recraft-v4"
    static let recraftRecraftV4Pro: Self = "recraft/recraft-v4-pro"
    static let recraftRecraftV41: Self = "recraft/recraft-v4.1"
    static let recraftRecraftV41Flash: Self = "recraft/recraft-v4.1-flash"
    static let recraftRecraftV41Pro: Self = "recraft/recraft-v4.1-pro"
    static let recraftRecraftV41Utility: Self = "recraft/recraft-v4.1-utility"
    static let recraftRecraftV41UtilityPro: Self = "recraft/recraft-v4.1-utility-pro"
    static let spacexaiGrokImagineImage: Self = "spacexai/grok-imagine-image"
    static let spacexaiGrokImagineImage20: Self = "spacexai/grok-imagine-image-2.0"
    static let topazWonder35: Self = "topaz/wonder-3.5"
}

public struct GatewayVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayVideoModelId {
    static let alibabaWanV25T2vPreview: Self = "alibaba/wan-v2.5-t2v-preview"
    static let alibabaWanV26I2v: Self = "alibaba/wan-v2.6-i2v"
    static let alibabaWanV26I2vFlash: Self = "alibaba/wan-v2.6-i2v-flash"
    static let alibabaWanV26R2v: Self = "alibaba/wan-v2.6-r2v"
    static let alibabaWanV26R2vFlash: Self = "alibaba/wan-v2.6-r2v-flash"
    static let alibabaWanV26T2v: Self = "alibaba/wan-v2.6-t2v"
    static let alibabaWanV27R2v: Self = "alibaba/wan-v2.7-r2v"
    static let alibabaWanV27T2v: Self = "alibaba/wan-v2.7-t2v"
    static let alibabaWanV30Video: Self = "alibaba/wan-v3.0-video"
    static let alibabaWanV30VideoPrime: Self = "alibaba/wan-v3.0-video-prime"
    static let bflFlux3Video: Self = "bfl/flux-3-video"
    static let bytedanceSeedance20: Self = "bytedance/seedance-2.0"
    static let bytedanceSeedance20Fast: Self = "bytedance/seedance-2.0-fast"
    static let bytedanceSeedance20Mini: Self = "bytedance/seedance-2.0-mini"
    static let bytedanceSeedance25: Self = "bytedance/seedance-2.5"
    static let bytedanceSeedanceV10Pro: Self = "bytedance/seedance-v1.0-pro"
    static let bytedanceSeedanceV10ProFast: Self = "bytedance/seedance-v1.0-pro-fast"
    static let bytedanceSeedanceV15Pro: Self = "bytedance/seedance-v1.5-pro"
    static let googleVeo30FastGenerate001: Self = "google/veo-3.0-fast-generate-001"
    static let googleVeo30Generate001: Self = "google/veo-3.0-generate-001"
    static let googleVeo31FastGenerate001: Self = "google/veo-3.1-fast-generate-001"
    static let googleVeo31Generate001: Self = "google/veo-3.1-generate-001"
    static let googleVeo31LiteGenerate001: Self = "google/veo-3.1-lite-generate-001"
    static let heygenHeygenVideo1: Self = "heygen/heygen-video-1"
    static let klingaiKlingV25TurboI2v: Self = "klingai/kling-v2.5-turbo-i2v"
    static let klingaiKlingV25TurboT2v: Self = "klingai/kling-v2.5-turbo-t2v"
    static let klingaiKlingV26I2v: Self = "klingai/kling-v2.6-i2v"
    static let klingaiKlingV26MotionControl: Self = "klingai/kling-v2.6-motion-control"
    static let klingaiKlingV26T2v: Self = "klingai/kling-v2.6-t2v"
    static let klingaiKlingV30I2v: Self = "klingai/kling-v3.0-i2v"
    static let klingaiKlingV30MotionControl: Self = "klingai/kling-v3.0-motion-control"
    static let klingaiKlingV30T2v: Self = "klingai/kling-v3.0-t2v"
    static let minimaxMinimaxH3: Self = "minimax/minimax-h3"
    static let minimaxMinimaxH3Max: Self = "minimax/minimax-h3-max"
    static let spacexaiGrokImagineVideo: Self = "spacexai/grok-imagine-video"
    static let spacexaiGrokImagineVideo15: Self = "spacexai/grok-imagine-video-1.5"
    static let spacexaiGrokImagineVideo15Lite: Self = "spacexai/grok-imagine-video-1.5-lite"
    static let topazProteus: Self = "topaz/proteus"
    static let topazStarlightPrecise26: Self = "topaz/starlight-precise-2.6"
}

public struct GatewayRerankingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayRerankingModelId {
    static let cohereRerankV35: Self = "cohere/rerank-v3.5"
    static let cohereRerankV4Fast: Self = "cohere/rerank-v4-fast"
    static let cohereRerankV4Pro: Self = "cohere/rerank-v4-pro"
    static let voyageRerank25: Self = "voyage/rerank-2.5"
    static let voyageRerank25Lite: Self = "voyage/rerank-2.5-lite"
    static let voyageRerank3: Self = "voyage/rerank-3"
    static let voyageRerank3Lite: Self = "voyage/rerank-3-lite"
}

public struct GatewaySpeechModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewaySpeechModelId {
    static let fishAudioDrama3: Self = "fish-audio/drama-3"
    static let fishAudioS1: Self = "fish-audio/s1"
    static let fishAudioS2Pro: Self = "fish-audio/s2-pro"
    static let fishAudioS21Pro: Self = "fish-audio/s2.1-pro"
    static let googleGemini38FlashLiteTts: Self = "google/gemini-3.8-flash-lite-tts"
    static let googleGemini38FlashTts: Self = "google/gemini-3.8-flash-tts"
    static let microsoftMaiVoice2: Self = "microsoft/mai-voice-2"
    static let microsoftMaiVoice2Flash: Self = "microsoft/mai-voice-2-flash"
    static let microsoftMaiVoice21: Self = "microsoft/mai-voice-2.1"
    static let microsoftMaiVoice21Flash: Self = "microsoft/mai-voice-2.1-flash"
    static let openaiTts1: Self = "openai/tts-1"
    static let openaiTts1Hd: Self = "openai/tts-1-hd"
    static let spacexaiGrokTts: Self = "spacexai/grok-tts"
}

public struct GatewayTranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayTranscriptionModelId {
    static let fishAudioTranscribe1: Self = "fish-audio/transcribe-1"
    static let googleGemini35Transcribe: Self = "google/gemini-3.5-transcribe"
    static let googleGemini35TranscribeLive: Self = "google/gemini-3.5-transcribe-live"
    static let microsoftMaiTranscribe2: Self = "microsoft/mai-transcribe-2"
    static let microsoftMaiTranscribe2Streaming: Self = "microsoft/mai-transcribe-2-streaming"
    static let openaiGPT4oMiniTranscribe: Self = "openai/gpt-4o-mini-transcribe"
    static let openaiGPT4oTranscribe: Self = "openai/gpt-4o-transcribe"
    static let openaiGPTRealtimeWhisper: Self = "openai/gpt-realtime-whisper"
    static let openaiWhisper1: Self = "openai/whisper-1"
    static let spacexaiGrokStt: Self = "spacexai/grok-stt"
}

public struct GatewayRealtimeModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension GatewayRealtimeModelId {
    static let googleGemini38Live: Self = "google/gemini-3.8-live"
    static let googleGemini38LiveExtendedThinking: Self = "google/gemini-3.8-live-extended-thinking"
    static let openaiGPTLive1: Self = "openai/gpt-live-1"
    static let openaiGPTRealtime15: Self = "openai/gpt-realtime-1.5"
    static let openaiGPTRealtime2: Self = "openai/gpt-realtime-2"
    static let openaiGPTRealtime21: Self = "openai/gpt-realtime-2.1"
    static let openaiGPTRealtimeMini: Self = "openai/gpt-realtime-mini"
    static let spacexaiGrokVoiceThinkFast10: Self = "spacexai/grok-voice-think-fast-1.0"
    static let spacexaiGrokVoiceThinkFast20: Self = "spacexai/grok-voice-think-fast-2.0"
}
