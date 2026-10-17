import Foundation
import AISDKProviderUtils

public struct CohereLanguageModelChatOptions: Codable, Sendable, Equatable {
    public struct Thinking: Codable, Sendable, Equatable {
        public enum ThinkingType: String, Codable, Sendable {
            case enabled, disabled
        }

        public var type: ThinkingType?
        public var tokenBudget: Double?

        public init(type: ThinkingType? = nil, tokenBudget: Double? = nil) {
            self.type = type
            self.tokenBudget = tokenBudget
        }

        private enum CodingKeys: String, CodingKey { case type, tokenBudget }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                type: container.contains(.type) ? container.decode(ThinkingType.self, forKey: .type) : nil,
                tokenBudget: container.contains(.tokenBudget) ? container.decode(Double.self, forKey: .tokenBudget) : nil
            )
        }
    }

    public var thinking: Thinking?

    public init(thinking: Thinking? = nil) { self.thinking = thinking }

    private enum CodingKeys: String, CodingKey { case thinking }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thinking = container.contains(.thinking) ? try container.decode(Thinking.self, forKey: .thinking) : nil
    }
}

public struct CohereImagePartProviderOptions: Codable, Sendable, Equatable {
    public enum Detail: String, Codable, Sendable {
        case auto, low, high
    }

    public var detail: Detail?

    public init(detail: Detail? = nil) { self.detail = detail }

    private enum CodingKeys: String, CodingKey { case detail }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detail = container.contains(.detail) ? try container.decode(Detail.self, forKey: .detail) : nil
    }
}

let cohereLanguageModelChatOptions = FlexibleSchema(
    Schema<CohereLanguageModelChatOptions>.codable(CohereLanguageModelChatOptions.self, jsonSchema: ["type": "object"])
)
let cohereImagePartProviderOptions = FlexibleSchema(
    Schema<CohereImagePartProviderOptions>.codable(CohereImagePartProviderOptions.self, jsonSchema: ["type": "object"])
)
