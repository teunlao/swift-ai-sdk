import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct MistralLanguageModelChatOptions: Sendable, Equatable, Codable {
    public var safePrompt: Bool?
    public var documentImageLimit: Double?
    public var documentPageLimit: Double?
    public var structuredOutputs: Bool?
    public var strictJsonSchema: Bool?
    public var parallelToolCalls: Bool?
    public var promptCacheKey: String?
    public var reasoningEffort: ReasoningEffort?

    public enum ReasoningEffort: String, Sendable, Codable { case high, none }

    public init(
        safePrompt: Bool? = nil,
        documentImageLimit: Double? = nil,
        documentPageLimit: Double? = nil,
        structuredOutputs: Bool? = nil,
        strictJsonSchema: Bool? = nil,
        parallelToolCalls: Bool? = nil,
        promptCacheKey: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.safePrompt = safePrompt
        self.documentImageLimit = documentImageLimit
        self.documentPageLimit = documentPageLimit
        self.structuredOutputs = structuredOutputs
        self.strictJsonSchema = strictJsonSchema
        self.parallelToolCalls = parallelToolCalls
        self.promptCacheKey = promptCacheKey
        self.reasoningEffort = reasoningEffort
    }

    private enum CodingKeys: String, CodingKey {
        case safePrompt, documentImageLimit, documentPageLimit, structuredOutputs
        case strictJsonSchema, parallelToolCalls, promptCacheKey, reasoningEffort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            safePrompt: container.contains(.safePrompt) ? container.decode(Bool.self, forKey: .safePrompt) : nil,
            documentImageLimit: container.contains(.documentImageLimit) ? container.decode(Double.self, forKey: .documentImageLimit) : nil,
            documentPageLimit: container.contains(.documentPageLimit) ? container.decode(Double.self, forKey: .documentPageLimit) : nil,
            structuredOutputs: container.contains(.structuredOutputs) ? container.decode(Bool.self, forKey: .structuredOutputs) : nil,
            strictJsonSchema: container.contains(.strictJsonSchema) ? container.decode(Bool.self, forKey: .strictJsonSchema) : nil,
            parallelToolCalls: container.contains(.parallelToolCalls) ? container.decode(Bool.self, forKey: .parallelToolCalls) : nil,
            promptCacheKey: container.contains(.promptCacheKey) ? container.decode(String.self, forKey: .promptCacheKey) : nil,
            reasoningEffort: container.contains(.reasoningEffort) ? container.decode(ReasoningEffort.self, forKey: .reasoningEffort) : nil
        )
    }
}

public let mistralLanguageModelChatOptions = FlexibleSchema(
    Schema<MistralLanguageModelChatOptions>.codable(
        MistralLanguageModelChatOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public struct MistralEmbeddingModelOptions: Sendable, Equatable, Codable {
    public var metadata: [String: JSONValue]?
    public var outputDimension: Int?
    public var outputDtype: OutputDtype?

    public enum OutputDtype: String, Sendable, Codable { case float, int8, uint8, binary, ubinary }

    public init(metadata: [String: JSONValue]? = nil, outputDimension: Int? = nil, outputDtype: OutputDtype? = nil) {
        self.metadata = metadata
        self.outputDimension = outputDimension
        self.outputDtype = outputDtype
    }

    private enum CodingKeys: String, CodingKey {
        case metadata, outputDimension, outputDtype
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            metadata: container.contains(.metadata) ? container.decode([String: JSONValue].self, forKey: .metadata) : nil,
            outputDimension: container.contains(.outputDimension) ? container.decode(Int.self, forKey: .outputDimension) : nil,
            outputDtype: container.contains(.outputDtype) ? container.decode(OutputDtype.self, forKey: .outputDtype) : nil
        )
    }
}

let mistralEmbeddingModelOptions = FlexibleSchema(
    Schema<MistralEmbeddingModelOptions>(
        jsonSchemaResolver: { .object(["type": .string("object")]) },
        validator: { value in
            do {
                let options = try JSONDecoder().decode(MistralEmbeddingModelOptions.self, from: JSONEncoder().encode(jsonValue(from: value)))
                if let dimension = options.outputDimension, dimension <= 0 {
                    throw InvalidArgumentError(argument: "outputDimension", message: "Must be a positive integer.")
                }
                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
