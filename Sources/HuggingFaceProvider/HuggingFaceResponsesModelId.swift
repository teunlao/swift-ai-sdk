import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/huggingface-responses-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct HuggingFaceResponsesModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public extension HuggingFaceResponsesModelId {
    static let llama31_8BInstruct: Self = "meta-llama/Llama-3.1-8B-Instruct"
    static let llama31_70BInstruct: Self = "meta-llama/Llama-3.1-70B-Instruct"
    static let llama31_405BInstruct: Self = "meta-llama/Llama-3.1-405B-Instruct"
    static let llama33_70BInstruct: Self = "meta-llama/Llama-3.3-70B-Instruct"
    static let llama3_8BInstruct: Self = "meta-llama/Meta-Llama-3-8B-Instruct"
    static let llama3_70BInstruct: Self = "meta-llama/Meta-Llama-3-70B-Instruct"
    static let llama32_3BInstruct: Self = "meta-llama/Llama-3.2-3B-Instruct"
    static let llama4Maverick17B128EInstruct: Self = "meta-llama/Llama-4-Maverick-17B-128E-Instruct"
    static let llama4Maverick17B128EInstructFP8: Self = "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8"
    static let llamaGuard412B: Self = "meta-llama/Llama-Guard-4-12B"
    static let deepSeekV31: Self = "deepseek-ai/DeepSeek-V3.1"
    static let deepSeekV30324: Self = "deepseek-ai/DeepSeek-V3-0324"
    static let deepSeekR1: Self = "deepseek-ai/DeepSeek-R1"
    static let deepSeekR10528: Self = "deepseek-ai/DeepSeek-R1-0528"
    static let deepSeekR1DistillQwen15B: Self = "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
    static let deepSeekR1DistillQwen7B: Self = "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B"
    static let deepSeekR1DistillQwen14B: Self = "deepseek-ai/DeepSeek-R1-Distill-Qwen-14B"
    static let deepSeekR1DistillQwen32B: Self = "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B"
    static let deepSeekR1DistillLlama8B: Self = "deepseek-ai/DeepSeek-R1-Distill-Llama-8B"
    static let deepSeekR1DistillLlama70B: Self = "deepseek-ai/DeepSeek-R1-Distill-Llama-70B"
    static let deepSeekProverV2671B: Self = "deepseek-ai/DeepSeek-Prover-V2-671B"
    static let qwen332B: Self = "Qwen/Qwen3-32B"
    static let qwen314B: Self = "Qwen/Qwen3-14B"
    static let qwen38B: Self = "Qwen/Qwen3-8B"
    static let qwen34B: Self = "Qwen/Qwen3-4B"
    static let qwen3Coder480BA35BInstruct: Self = "Qwen/Qwen3-Coder-480B-A35B-Instruct"
    static let qwen3Coder480BA35BInstructFP8: Self = "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"
    static let qwen330BA3B: Self = "Qwen/Qwen3-30B-A3B"
    static let qwen25VL7BInstruct: Self = "Qwen/Qwen2.5-VL-7B-Instruct"
    static let qwen257BInstruct: Self = "Qwen/Qwen2.5-7B-Instruct"
    static let qwen25Coder7BInstruct: Self = "Qwen/Qwen2.5-Coder-7B-Instruct"
    static let qwen25Coder32BInstruct: Self = "Qwen/Qwen2.5-Coder-32B-Instruct"
    static let gemma29BIt: Self = "google/gemma-2-9b-it"
    static let gemma327BIt: Self = "google/gemma-3-27b-it"
    static let kimiK2Instruct: Self = "moonshotai/Kimi-K2-Instruct"
}
