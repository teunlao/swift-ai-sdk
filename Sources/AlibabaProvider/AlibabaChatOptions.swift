import Foundation
import AISDKProviderUtils

public struct AlibabaChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public static let qwen37Max: Self = "qwen3.7-max"
    public static let qwen3Max: Self = "qwen3-max"
    public static let qwen3MaxPreview: Self = "qwen3-max-preview"
    public static let qwenPlus: Self = "qwen-plus"
    public static let qwenPlusLatest: Self = "qwen-plus-latest"
    public static let qwenFlash: Self = "qwen-flash"
    public static let qwenTurbo: Self = "qwen-turbo"
    public static let qwenTurboLatest: Self = "qwen-turbo-latest"
    public static let qwen3235bA22b: Self = "qwen3-235b-a22b"
    public static let qwen332b: Self = "qwen3-32b"
    public static let qwen330bA3b: Self = "qwen3-30b-a3b"
    public static let qwen314b: Self = "qwen3-14b"
    public static let qwen3Next80bA3bThinking: Self = "qwen3-next-80b-a3b-thinking"
    public static let qwen3235bA22bThinking2507: Self = "qwen3-235b-a22b-thinking-2507"
    public static let qwen330bA3bThinking2507: Self = "qwen3-30b-a3b-thinking-2507"
    public static let qwqPlus: Self = "qwq-plus"
    public static let qwqPlusLatest: Self = "qwq-plus-latest"
    public static let qwq32b: Self = "qwq-32b"
    public static let qwenCoder: Self = "qwen-coder"
    public static let qwen3CoderPlus: Self = "qwen3-coder-plus"
    public static let qwen3CoderFlash: Self = "qwen3-coder-flash"
}

public struct AlibabaLanguageModelChatOptions: Codable, Sendable, Equatable {
    public var enableThinking: Bool?
    public var thinkingBudget: Double?
    public var preserveThinking: Bool?
    public var parallelToolCalls: Bool?
    public init(enableThinking: Bool? = nil, thinkingBudget: Double? = nil, preserveThinking: Bool? = nil, parallelToolCalls: Bool? = nil) {
        self.enableThinking = enableThinking
        self.thinkingBudget = thinkingBudget
        self.preserveThinking = preserveThinking
        self.parallelToolCalls = parallelToolCalls
    }
    private enum CodingKeys: String, CodingKey { case enableThinking, thinkingBudget, preserveThinking, parallelToolCalls }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            enableThinking: container.contains(.enableThinking) ? container.decode(Bool.self, forKey: .enableThinking) : nil,
            thinkingBudget: container.contains(.thinkingBudget) ? container.decode(Double.self, forKey: .thinkingBudget) : nil,
            preserveThinking: container.contains(.preserveThinking) ? container.decode(Bool.self, forKey: .preserveThinking) : nil,
            parallelToolCalls: container.contains(.parallelToolCalls) ? container.decode(Bool.self, forKey: .parallelToolCalls) : nil
        )
        if let thinkingBudget, thinkingBudget <= 0 || !thinkingBudget.isFinite {
            throw DecodingError.dataCorruptedError(forKey: .thinkingBudget, in: container, debugDescription: "Expected a positive thinking budget")
        }
    }
}
let alibabaLanguageModelChatOptions = FlexibleSchema(Schema<AlibabaLanguageModelChatOptions>.codable(AlibabaLanguageModelChatOptions.self, jsonSchema: ["type": "object"]))

func supportsAlibabaJSONSchema(_ modelId: String) -> Bool {
    ["qwen3.7-plus", "qwen3.7-flash", "qwen3.7-max", "qwen3.8-max", "qwen3.8-flash"].contains { modelId == $0 || modelId.hasPrefix($0 + "-") }
}
func supportsAlibabaPreservedThinking(_ modelId: String) -> Bool {
    ["kimi-k2.7-code", "qwen3.6-max-preview", "qwen3.6-plus", "qwen3.6-plus-2026-04-02", "qwen3.7-flash", "qwen3.7-flash-2026-07-15", "qwen3.7-max", "qwen3.7-max-2026-05-17", "qwen3.7-max-2026-05-20", "qwen3.7-max-2026-06-08", "qwen3.7-max-preview", "qwen3.7-plus", "qwen3.7-plus-2026-05-26", "qwen3.8-flash", "qwen3.8-max", "qwen3.8-max-0902"].contains(modelId)
}
