import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct BedrockChatModelSettings: Sendable {
    public enum ModelFamily: String, Sendable { case anthropic }
    public var modelFamily: ModelFamily?

    public init(modelFamily: ModelFamily? = nil) {
        self.modelFamily = modelFamily
    }
}

public enum BedrockReasoningType: String, Sendable, Codable { case enabled, disabled, adaptive }
public enum BedrockMaxReasoningEffort: String, Sendable, Codable { case low, medium, high, xhigh, max }
public enum BedrockThinkingDisplay: String, Sendable, Codable { case omitted, summarized }
public enum BedrockStructuredOutputMode: String, Sendable, Codable { case outputFormat, jsonTool, auto }
public enum BedrockServiceTier: String, Sendable, Codable { case reserved, priority, `default`, flex }

public struct BedrockReasoningConfig: Sendable, Equatable, Codable {
    public var type: BedrockReasoningType?
    public var budgetTokens: Int?
    public var maxReasoningEffort: BedrockMaxReasoningEffort?
    public var display: BedrockThinkingDisplay?

    public init(type: BedrockReasoningType? = nil, budgetTokens: Int? = nil, maxReasoningEffort: BedrockMaxReasoningEffort? = nil, display: BedrockThinkingDisplay? = nil) {
        self.type = type
        self.budgetTokens = budgetTokens
        self.maxReasoningEffort = maxReasoningEffort
        self.display = display
    }
}

public struct BedrockProviderOptions: Sendable, Equatable, Codable {
    public var additionalModelRequestFields: [String: JSONValue]?
    public var reasoningConfig: BedrockReasoningConfig?
    public var anthropicBeta: [String]?
    public var structuredOutputMode: BedrockStructuredOutputMode?
    public var serviceTier: BedrockServiceTier?
    public var requestMetadata: [String: String]?

    public init(additionalModelRequestFields: [String: JSONValue]? = nil, reasoningConfig: BedrockReasoningConfig? = nil, anthropicBeta: [String]? = nil, structuredOutputMode: BedrockStructuredOutputMode? = nil, serviceTier: BedrockServiceTier? = nil, requestMetadata: [String: String]? = nil) {
        self.additionalModelRequestFields = additionalModelRequestFields
        self.reasoningConfig = reasoningConfig
        self.anthropicBeta = anthropicBeta
        self.structuredOutputMode = structuredOutputMode
        self.serviceTier = serviceTier
        self.requestMetadata = requestMetadata
    }
}

public struct BedrockFilePartProviderOptions: Sendable, Equatable, Codable {
    public struct Citations: Sendable, Equatable, Codable {
        public var enabled: Bool
        public init(enabled: Bool) { self.enabled = enabled }
    }
    public var citations: Citations?
    public init(citations: Citations? = nil) { self.citations = citations }
}

public struct BedrockTextPartProviderOptions: Sendable, Equatable, Codable {
    public enum Qualifier: String, Sendable, Codable { case groundingSource = "grounding_source", query, guardContent = "guard_content" }
    public var guardContent: Bool?
    public var guardContentQualifiers: [Qualifier]?
    public init(guardContent: Bool? = nil, guardContentQualifiers: [Qualifier]? = nil) {
        self.guardContent = guardContent
        self.guardContentQualifiers = guardContentQualifiers
    }
}

public struct BedrockImagePartProviderOptions: Sendable, Equatable, Codable {
    public var guardContent: Bool?
    public init(guardContent: Bool? = nil) { self.guardContent = guardContent }
}

struct BedrockAnthropicOptions: Codable, Sendable {
    let disableParallelToolUse: Bool?
    let structuredOutputMode: BedrockStructuredOutputMode?
}

public let bedrockProviderOptionsSchema = bedrockOptionalFieldsSchema(BedrockProviderOptions.self, fields: ["additionalModelRequestFields", "reasoningConfig", "anthropicBeta", "structuredOutputMode", "serviceTier", "requestMetadata"], nestedFields: ["reasoningConfig": ["type", "budgetTokens", "maxReasoningEffort", "display"]])
public let bedrockFilePartProviderOptionsSchema = bedrockOptionalFieldsSchema(BedrockFilePartProviderOptions.self, fields: ["citations"])
public let bedrockTextPartProviderOptionsSchema = bedrockOptionalFieldsSchema(BedrockTextPartProviderOptions.self, fields: ["guardContent", "guardContentQualifiers"])
public let bedrockImagePartProviderOptionsSchema = bedrockOptionalFieldsSchema(BedrockImagePartProviderOptions.self, fields: ["guardContent"])
let bedrockAnthropicOptionsSchema = bedrockOptionalFieldsSchema(BedrockAnthropicOptions.self, fields: ["disableParallelToolUse", "structuredOutputMode"])

func bedrockOptionsSchema<T: Decodable & Sendable>(_ type: T.Type) -> FlexibleSchema<T> {
    FlexibleSchema(Schema<T>.codable(type, jsonSchema: .object(["type": .string("object")])))
}

func bedrockOptionalFieldsSchema<T: Decodable & Sendable>(_ type: T.Type, fields: [String], nestedFields: [String: [String]] = [:]) -> FlexibleSchema<T> {
    let schema = Schema<T>.codable(type, jsonSchema: .object(["type": .string("object")]))
    return FlexibleSchema(Schema<T>(jsonSchemaResolver: { try await schema.jsonSchema() }, validator: { value in
        if let object = value as? [String: Any] {
            var nullField = fields.first { object[$0] is NSNull }
            for (key, fields) in nestedFields {
                if let nested = object[key] as? [String: Any], let field = fields.first(where: { nested[$0] is NSNull }) { nullField = "\(key).\(field)" }
            }
            if let nullField {
                return .failure(error: TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "amazonBedrock", issues: "\(nullField) must not be null")))
            }
        }
        return await schema.validate(value)
    }))
}

func parseBedrockOptions<T: Sendable>(providerOptions: SharedV4ProviderOptions?, schema: FlexibleSchema<T>) async throws -> T? {
    try await parseProviderOptions(provider: providerOptions?["amazonBedrock"] != nil ? "amazonBedrock" : "bedrock", providerOptions: providerOptions, schema: schema)
}

func isBedrockAnthropicModel(_ modelId: String, modelFamily: BedrockChatModelSettings.ModelFamily? = nil, reasoningBudgetTokens: Int? = nil) -> Bool {
    modelFamily == .anthropic || modelId.contains("anthropic") || (modelId.contains(":application-inference-profile/") && reasoningBudgetTokens != nil)
}

func bedrockSupportsStrictTools(_ modelId: String) -> Bool {
    guard modelId.contains("claude-") else { return true }
    return [
        "claude-(?:instant|v?2|3)(?=[-.:]|$)",
        "claude-(?:opus|sonnet)-4(?:-\\d{8})?(?:-v\\d+)?(?=[:.]|$)",
        "claude-opus-4-(?:1|5|6)(?=[-.:]|$)",
        "claude-sonnet-4-(?:5|6)(?=[-.:]|$)",
        "claude-haiku-4-5(?=[-.:]|$)"
    ].contains { modelId.range(of: $0, options: .regularExpression) != nil }
}

func bedrockSupportsNativeStructuredOutput(_ modelId: String) -> Bool {
    bedrockSupportsStrictTools(modelId) && modelId.range(of: "claude-(?:sonnet-4-6|haiku-4-5)(?=[-.:]|$)", options: .regularExpression) == nil
}
