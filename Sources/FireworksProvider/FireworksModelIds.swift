import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fireworks/src/fireworks-chat-options.ts
// Ported from packages/fireworks/src/fireworks-completion-options.ts
// Ported from packages/fireworks/src/fireworks-embedding-options.ts
// Ported from packages/fireworks/src/fireworks-image-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct FireworksChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension FireworksChatModelId {
    static let deepseekV3: Self = "accounts/fireworks/models/deepseek-v3"
    static let llamaV3p3_70bInstruct: Self = "accounts/fireworks/models/llama-v3p3-70b-instruct"
    static let llamaV3p2_3bInstruct: Self = "accounts/fireworks/models/llama-v3p2-3b-instruct"
    static let llamaV3p1_405bInstruct: Self = "accounts/fireworks/models/llama-v3p1-405b-instruct"
    static let llamaV3p1_8bInstruct: Self = "accounts/fireworks/models/llama-v3p1-8b-instruct"
    static let mixtral8x7bInstruct: Self = "accounts/fireworks/models/mixtral-8x7b-instruct"
    static let mixtral8x22bInstruct: Self = "accounts/fireworks/models/mixtral-8x22b-instruct"
    static let mixtral8x7bInstructHF: Self = "accounts/fireworks/models/mixtral-8x7b-instruct-hf"
    static let qwen2p5Coder32bInstruct: Self = "accounts/fireworks/models/qwen2p5-coder-32b-instruct"
    static let qwen2p5_72bInstruct: Self = "accounts/fireworks/models/qwen2p5-72b-instruct"
    static let qwenQwq32bPreview: Self = "accounts/fireworks/models/qwen-qwq-32b-preview"
    static let qwen2VL72bInstruct: Self = "accounts/fireworks/models/qwen2-vl-72b-instruct"
    static let llamaV3p2_11bVisionInstruct: Self = "accounts/fireworks/models/llama-v3p2-11b-vision-instruct"
    static let qwq32b: Self = "accounts/fireworks/models/qwq-32b"
    static let yiLarge: Self = "accounts/fireworks/models/yi-large"
    static let kimiK2Instruct: Self = "accounts/fireworks/models/kimi-k2-instruct"
}

public struct FireworksCompletionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension FireworksCompletionModelId {
    static let llamaV3_8bInstruct: Self = "accounts/fireworks/models/llama-v3-8b-instruct"
    static let llamaV2_34bCode: Self = "accounts/fireworks/models/llama-v2-34b-code"
}

public struct FireworksEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension FireworksEmbeddingModelId {
    static let nomicEmbedTextV15: Self = "nomic-ai/nomic-embed-text-v1.5"
}

public struct FireworksImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension FireworksImageModelId {
    static let flux1DevFP8: Self = "accounts/fireworks/models/flux-1-dev-fp8"
    static let flux1SchnellFP8: Self = "accounts/fireworks/models/flux-1-schnell-fp8"
    static let playgroundV25_1024pxAesthetic: Self = "accounts/fireworks/models/playground-v2-5-1024px-aesthetic"
    static let japaneseStableDiffusionXL: Self = "accounts/fireworks/models/japanese-stable-diffusion-xl"
    static let playgroundV2_1024pxAesthetic: Self = "accounts/fireworks/models/playground-v2-1024px-aesthetic"
    static let ssd1b: Self = "accounts/fireworks/models/SSD-1B"
    static let stableDiffusionXL1024v10: Self = "accounts/fireworks/models/stable-diffusion-xl-1024-v1-0"
}
