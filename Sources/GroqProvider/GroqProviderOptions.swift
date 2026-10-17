import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GroqReasoningFormat: String, Sendable, Equatable, Codable { case parsed, raw, hidden }
public enum GroqServiceTier: String, Sendable, Equatable, Codable {
    case onDemand = "on_demand"
    case performance, flex, auto
}

public struct GroqLanguageModelChatOptions: Sendable, Equatable, Codable {
    public enum ReasoningEffort: String, Sendable, Codable { case none, `default`, low, medium, high }
    public var reasoningFormat: GroqReasoningFormat?
    public var reasoningEffort: ReasoningEffort?
    public var parallelToolCalls: Bool?
    public var user: String?
    public var structuredOutputs: Bool?
    public var strictJsonSchema: Bool?
    public var serviceTier: GroqServiceTier?

    public init(reasoningFormat: GroqReasoningFormat? = nil, reasoningEffort: ReasoningEffort? = nil,
                parallelToolCalls: Bool? = nil, user: String? = nil, structuredOutputs: Bool? = nil,
                strictJsonSchema: Bool? = nil, serviceTier: GroqServiceTier? = nil) {
        self.reasoningFormat = reasoningFormat
        self.reasoningEffort = reasoningEffort
        self.parallelToolCalls = parallelToolCalls
        self.user = user
        self.structuredOutputs = structuredOutputs
        self.strictJsonSchema = strictJsonSchema
        self.serviceTier = serviceTier
    }

    private enum CodingKeys: String, CodingKey {
        case reasoningFormat, reasoningEffort, parallelToolCalls, user, structuredOutputs, strictJsonSchema, serviceTier
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reasoningFormat: container.contains(.reasoningFormat) ? container.decode(GroqReasoningFormat.self, forKey: .reasoningFormat) : nil,
            reasoningEffort: container.contains(.reasoningEffort) ? container.decode(ReasoningEffort.self, forKey: .reasoningEffort) : nil,
            parallelToolCalls: container.contains(.parallelToolCalls) ? container.decode(Bool.self, forKey: .parallelToolCalls) : nil,
            user: container.contains(.user) ? container.decode(String.self, forKey: .user) : nil,
            structuredOutputs: container.contains(.structuredOutputs) ? container.decode(Bool.self, forKey: .structuredOutputs) : nil,
            strictJsonSchema: container.contains(.strictJsonSchema) ? container.decode(Bool.self, forKey: .strictJsonSchema) : nil,
            serviceTier: container.contains(.serviceTier) ? container.decode(GroqServiceTier.self, forKey: .serviceTier) : nil
        )
    }
}

let groqLanguageModelChatOptions = FlexibleSchema(
    Schema<GroqLanguageModelChatOptions>.codable(GroqLanguageModelChatOptions.self, jsonSchema: ["type": "object"])
)
