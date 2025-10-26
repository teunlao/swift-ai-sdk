import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepinfra/src/deepinfra-*-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepInfraChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension DeepInfraChatModelId {
    static let model01AiYi34BChat: Self = "01-ai/Yi-34B-Chat"
    static let austismChronosHermes13bV2: Self = "Austism/chronos-hermes-13b-v2"
    static let bigcodeStarcoder215bInstructV01: Self = "bigcode/starcoder2-15b-instruct-v0.1"
    static let bigcodeStarcoder215b: Self = "bigcode/starcoder2-15b"
    static let codellamaCodeLlama34bInstructHf: Self = "codellama/CodeLlama-34b-Instruct-hf"
    static let codellamaCodeLlama70bInstructHf: Self = "codellama/CodeLlama-70b-Instruct-hf"
    static let cognitivecomputationsDolphin26Mixtral8x7b: Self = "cognitivecomputations/dolphin-2.6-mixtral-8x7b"
    static let cognitivecomputationsDolphin291Llama370b: Self = "cognitivecomputations/dolphin-2.9.1-llama-3-70b"
    static let databricksDbrxInstruct: Self = "databricks/dbrx-instruct"
    static let deepinfraAiroboros70b: Self = "deepinfra/airoboros-70b"
    static let deepseekAiDeepSeekV3: Self = "deepseek-ai/DeepSeek-V3"
    static let googleCodegemma7bIt: Self = "google/codegemma-7b-it"
    static let googleGemma117bIt: Self = "google/gemma-1.1-7b-it"
    static let googleGemma227bIt: Self = "google/gemma-2-27b-it"
    static let googleGemma29bIt: Self = "google/gemma-2-9b-it"
    static let grypheMythoMaxL213bTurbo: Self = "Gryphe/MythoMax-L2-13b-turbo"
    static let grypheMythoMaxL213b: Self = "Gryphe/MythoMax-L2-13b"
    static let huggingfaceh4ZephyrOrpo141bA35bV01: Self = "HuggingFaceH4/zephyr-orpo-141b-A35b-v0.1"
    static let koboldaiLLaMA213BTiefighter: Self = "KoboldAI/LLaMA2-13B-Tiefighter"
    static let lizpreciatiorLzlv70bFp16Hf: Self = "lizpreciatior/lzlv_70b_fp16_hf"
    static let mattshumerReflectionLlama3170B: Self = "mattshumer/Reflection-Llama-3.1-70B"
    static let metaLlamaLlama213bChatHf: Self = "meta-llama/Llama-2-13b-chat-hf"
    static let metaLlamaLlama270bChatHf: Self = "meta-llama/Llama-2-70b-chat-hf"
    static let metaLlamaLlama27bChatHf: Self = "meta-llama/Llama-2-7b-chat-hf"
    static let metaLlamaLlama3211BVisionInstruct: Self = "meta-llama/Llama-3.2-11B-Vision-Instruct"
    static let metaLlamaLlama321BInstruct: Self = "meta-llama/Llama-3.2-1B-Instruct"
    static let metaLlamaLlama323BInstruct: Self = "meta-llama/Llama-3.2-3B-Instruct"
    static let metaLlamaLlama3290BVisionInstruct: Self = "meta-llama/Llama-3.2-90B-Vision-Instruct"
    static let metaLlamaLlama3370BInstructTurbo: Self = "meta-llama/Llama-3.3-70B-Instruct-Turbo"
    static let metaLlamaLlama3370BInstruct: Self = "meta-llama/Llama-3.3-70B-Instruct"
    static let metaLlamaLlama4Maverick17B128EInstructFP8: Self = "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8"
    static let metaLlamaLlama4Scout17B16EInstruct: Self = "meta-llama/Llama-4-Scout-17B-16E-Instruct"
    static let metaLlamaMetaLlama370BInstruct: Self = "meta-llama/Meta-Llama-3-70B-Instruct"
    static let metaLlamaMetaLlama38BInstruct: Self = "meta-llama/Meta-Llama-3-8B-Instruct"
    static let metaLlamaMetaLlama31405BInstruct: Self = "meta-llama/Meta-Llama-3.1-405B-Instruct"
    static let metaLlamaMetaLlama3170BInstructTurbo: Self = "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"
    static let metaLlamaMetaLlama3170BInstruct: Self = "meta-llama/Meta-Llama-3.1-70B-Instruct"
    static let metaLlamaMetaLlama318BInstructTurbo: Self = "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"
    static let metaLlamaMetaLlama318BInstruct: Self = "meta-llama/Meta-Llama-3.1-8B-Instruct"
    static let microsoftPhi3Medium4kInstruct: Self = "microsoft/Phi-3-medium-4k-instruct"
    static let microsoftWizardLM27B: Self = "microsoft/WizardLM-2-7B"
    static let microsoftWizardLM28x22B: Self = "microsoft/WizardLM-2-8x22B"
    static let mistralaiMistral7BInstructV01: Self = "mistralai/Mistral-7B-Instruct-v0.1"
    static let mistralaiMistral7BInstructV02: Self = "mistralai/Mistral-7B-Instruct-v0.2"
    static let mistralaiMistral7BInstructV03: Self = "mistralai/Mistral-7B-Instruct-v0.3"
    static let mistralaiMistralNemoInstruct2407: Self = "mistralai/Mistral-Nemo-Instruct-2407"
    static let mistralaiMixtral8x22BInstructV01: Self = "mistralai/Mixtral-8x22B-Instruct-v0.1"
    static let mistralaiMixtral8x22BV01: Self = "mistralai/Mixtral-8x22B-v0.1"
    static let mistralaiMixtral8x7BInstructV01: Self = "mistralai/Mixtral-8x7B-Instruct-v0.1"
    static let nousresearchHermes3Llama31405B: Self = "NousResearch/Hermes-3-Llama-3.1-405B"
    static let nvidiaLlama31Nemotron70BInstruct: Self = "nvidia/Llama-3.1-Nemotron-70B-Instruct"
    static let nvidiaNemotron4340BInstruct: Self = "nvidia/Nemotron-4-340B-Instruct"
    static let openbmbMiniCPMLlama3V25: Self = "openbmb/MiniCPM-Llama3-V-2_5"
    static let openchatOpenchat35: Self = "openchat/openchat_3.5"
    static let openchatOpenchat368b: Self = "openchat/openchat-3.6-8b"
    static let phindPhindCodeLlama34BV2: Self = "Phind/Phind-CodeLlama-34B-v2"
    static let qwenQwen272BInstruct: Self = "Qwen/Qwen2-72B-Instruct"
    static let qwenQwen27BInstruct: Self = "Qwen/Qwen2-7B-Instruct"
    static let qwenQwen2572BInstruct: Self = "Qwen/Qwen2.5-72B-Instruct"
    static let qwenQwen257BInstruct: Self = "Qwen/Qwen2.5-7B-Instruct"
    static let qwenQwen25Coder32BInstruct: Self = "Qwen/Qwen2.5-Coder-32B-Instruct"
    static let qwenQwen25Coder7B: Self = "Qwen/Qwen2.5-Coder-7B"
    static let qwenQwQ32BPreview: Self = "Qwen/QwQ-32B-Preview"
    static let sao10kL370BEuryaleV21: Self = "Sao10K/L3-70B-Euryale-v2.1"
    static let sao10kL38BLunarisV1: Self = "Sao10K/L3-8B-Lunaris-v1"
    static let sao10kL3170BEuryaleV22: Self = "Sao10K/L3.1-70B-Euryale-v2.2"
}

public typealias DeepInfraCompletionModelId = DeepInfraChatModelId

public struct DeepInfraEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension DeepInfraEmbeddingModelId {
    static let baaiBgeBaseEnV15: Self = "BAAI/bge-base-en-v1.5"
    static let baaiBgeLargeEnV15: Self = "BAAI/bge-large-en-v1.5"
    static let baaiBgeM3: Self = "BAAI/bge-m3"
    static let intfloatE5BaseV2: Self = "intfloat/e5-base-v2"
    static let intfloatE5LargeV2: Self = "intfloat/e5-large-v2"
    static let intfloatMultilingualE5Large: Self = "intfloat/multilingual-e5-large"
    static let sentenceTransformersAllMiniLML12V2: Self = "sentence-transformers/all-MiniLM-L12-v2"
    static let sentenceTransformersAllMiniLML6V2: Self = "sentence-transformers/all-MiniLM-L6-v2"
    static let sentenceTransformersAllMpnetBaseV2: Self = "sentence-transformers/all-mpnet-base-v2"
    static let sentenceTransformersClipViTB32: Self = "sentence-transformers/clip-ViT-B-32"
    static let sentenceTransformersClipViTB32MultilingualV1: Self = "sentence-transformers/clip-ViT-B-32-multilingual-v1"
    static let sentenceTransformersMultiQaMpnetBaseDotV1: Self = "sentence-transformers/multi-qa-mpnet-base-dot-v1"
    static let sentenceTransformersParaphraseMiniLML6V2: Self = "sentence-transformers/paraphrase-MiniLM-L6-v2"
    static let shibing624Text2vecBaseChinese: Self = "shibing624/text2vec-base-chinese"
    static let thenlperGteBase: Self = "thenlper/gte-base"
    static let thenlperGteLarge: Self = "thenlper/gte-large"
}

public struct DeepInfraImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension DeepInfraImageModelId {
    static let stabilityaiSd35: Self = "stabilityai/sd3.5"
    static let blackForestLabsFLUX11Pro: Self = "black-forest-labs/FLUX-1.1-pro"
    static let blackForestLabsFLUX1Schnell: Self = "black-forest-labs/FLUX-1-schnell"
    static let blackForestLabsFLUX1Dev: Self = "black-forest-labs/FLUX-1-dev"
    static let blackForestLabsFLUXPro: Self = "black-forest-labs/FLUX-pro"
    static let stabilityaiSd35Medium: Self = "stabilityai/sd3.5-medium"
    static let stabilityaiSdxlTurbo: Self = "stabilityai/sdxl-turbo"
}

