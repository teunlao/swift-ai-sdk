import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/togetherai-*-options.ts and togetherai-image-settings.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct TogetherAIChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension TogetherAIChatModelId {
    static let metaLlamaLlama3370BInstructTurbo: Self = "meta-llama/Llama-3.3-70B-Instruct-Turbo"
    static let metaLlamaMetaLlama318BInstructTurbo: Self = "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"
    static let metaLlamaMetaLlama3170BInstructTurbo: Self = "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"
    static let metaLlamaMetaLlama31405BInstructTurbo: Self = "meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo"
    static let metaLlamaMetaLlama38BInstructTurbo: Self = "meta-llama/Meta-Llama-3-8B-Instruct-Turbo"
    static let metaLlamaMetaLlama370BInstructTurbo: Self = "meta-llama/Meta-Llama-3-70B-Instruct-Turbo"
    static let metaLlamaLlama323BInstructTurbo: Self = "meta-llama/Llama-3.2-3B-Instruct-Turbo"
    static let metaLlamaMetaLlama38BInstructLite: Self = "meta-llama/Meta-Llama-3-8B-Instruct-Lite"
    static let metaLlamaMetaLlama370BInstructLite: Self = "meta-llama/Meta-Llama-3-70B-Instruct-Lite"
    static let metaLlamaLlama38BChatHf: Self = "meta-llama/Llama-3-8b-chat-hf"
    static let metaLlamaLlama370BChatHf: Self = "meta-llama/Llama-3-70b-chat-hf"
    static let nvidiaLlama31Nemotron70BInstructHF: Self = "nvidia/Llama-3.1-Nemotron-70B-Instruct-HF"
    static let qwenQwen25Coder32BInstruct: Self = "Qwen/Qwen2.5-Coder-32B-Instruct"
    static let qwenQwQ32BPreview: Self = "Qwen/QwQ-32B-Preview"
    static let microsoftWizardLM28x22B: Self = "microsoft/WizardLM-2-8x22B"
    static let googleGemma227bIt: Self = "google/gemma-2-27b-it"
    static let googleGemma29bIt: Self = "google/gemma-2-9b-it"
    static let databricksDbrxInstruct: Self = "databricks/dbrx-instruct"
    static let deepseekAiDeepseekLlm67bChat: Self = "deepseek-ai/deepseek-llm-67b-chat"
    static let deepseekAiDeepSeekV3: Self = "deepseek-ai/DeepSeek-V3"
    static let googleGemma2bIt: Self = "google/gemma-2b-it"
    static let grypheMythoMaxL213b: Self = "Gryphe/MythoMax-L2-13b"
    static let metaLlamaLlama213bChatHf: Self = "meta-llama/Llama-2-13b-chat-hf"
    static let mistralaiMistral7BInstructV01: Self = "mistralai/Mistral-7B-Instruct-v0.1"
    static let mistralaiMistral7BInstructV02: Self = "mistralai/Mistral-7B-Instruct-v0.2"
    static let mistralaiMistral7BInstructV03: Self = "mistralai/Mistral-7B-Instruct-v0.3"
    static let mistralaiMixtral8x7BInstructV01: Self = "mistralai/Mixtral-8x7B-Instruct-v0.1"
    static let mistralaiMixtral8x22BInstructV01: Self = "mistralai/Mixtral-8x22B-Instruct-v0.1"
    static let nousresearchNousHermes2Mixtral8x7BDPO: Self = "NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO"
    static let qwenQwen257BInstructTurbo: Self = "Qwen/Qwen2.5-7B-Instruct-Turbo"
    static let qwenQwen2572BInstructTurbo: Self = "Qwen/Qwen2.5-72B-Instruct-Turbo"
    static let qwenQwen272BInstruct: Self = "Qwen/Qwen2-72B-Instruct"
    static let upstageSOLAR107BInstructV10: Self = "upstage/SOLAR-10.7B-Instruct-v1.0"
}

public struct TogetherAICompletionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension TogetherAICompletionModelId {
    static let metaLlamaLlama270bHf: Self = "meta-llama/Llama-2-70b-hf"
    static let mistralaiMistral7BV01: Self = "mistralai/Mistral-7B-v0.1"
    static let mistralaiMixtral8x7BV01: Self = "mistralai/Mixtral-8x7B-v0.1"
    static let metaLlamaLlamaGuard7b: Self = "Meta-Llama/Llama-Guard-7b"
    static let codellamaCodeLlama34bInstructHf: Self = "codellama/CodeLlama-34b-Instruct-hf"
    static let qwenQwen25Coder32BInstruct: Self = "Qwen/Qwen2.5-Coder-32B-Instruct"
}

public struct TogetherAIEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension TogetherAIEmbeddingModelId {
    static let togethercomputerM2Bert80M2kRetrieval: Self = "togethercomputer/m2-bert-80M-2k-retrieval"
    static let togethercomputerM2Bert80M32kRetrieval: Self = "togethercomputer/m2-bert-80M-32k-retrieval"
    static let togethercomputerM2Bert80M8kRetrieval: Self = "togethercomputer/m2-bert-80M-8k-retrieval"
    static let whereisaiUAELargeV1: Self = "WhereIsAI/UAE-Large-V1"
    static let baaiBgeLargeEnV15: Self = "BAAI/bge-large-en-v1.5"
    static let baaiBgeBaseEnV15: Self = "BAAI/bge-base-en-v1.5"
    static let sentenceTransformersMsmarcoBertBaseDotV5: Self = "sentence-transformers/msmarco-bert-base-dot-v5"
    static let bertBaseUncased: Self = "bert-base-uncased"
}

public struct TogetherAIImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension TogetherAIImageModelId {
    static let stabilityaiStableDiffusionXLBase10: Self = "stabilityai/stable-diffusion-xl-base-1.0"
    static let blackForestLabsFLUX1Dev: Self = "black-forest-labs/FLUX.1-dev"
    static let blackForestLabsFLUX1DevLora: Self = "black-forest-labs/FLUX.1-dev-lora"
    static let blackForestLabsFLUX1Schnell: Self = "black-forest-labs/FLUX.1-schnell"
    static let blackForestLabsFLUX1Canny: Self = "black-forest-labs/FLUX.1-canny"
    static let blackForestLabsFLUX1Depth: Self = "black-forest-labs/FLUX.1-depth"
    static let blackForestLabsFLUX1Redux: Self = "black-forest-labs/FLUX.1-redux"
    static let blackForestLabsFLUX11Pro: Self = "black-forest-labs/FLUX.1.1-pro"
    static let blackForestLabsFLUX1Pro: Self = "black-forest-labs/FLUX.1-pro"
    static let blackForestLabsFLUX1SchnellFree: Self = "black-forest-labs/FLUX.1-schnell-Free"
    static let blackForestLabsFLUX1KontextPro: Self = "black-forest-labs/FLUX.1-kontext-pro"
    static let blackForestLabsFLUX1KontextMax: Self = "black-forest-labs/FLUX.1-kontext-max"
    static let blackForestLabsFLUX1KontextDev: Self = "black-forest-labs/FLUX.1-kontext-dev"
}

public struct TogetherAIRerankingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension TogetherAIRerankingModelId {
    static let salesforceLlamaRankV1: Self = "Salesforce/Llama-Rank-v1"
    static let mixedbreadAiMxbaiRerankLargeV2: Self = "mixedbread-ai/Mxbai-Rerank-Large-V2"
}

