import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct HuggingFaceResponsesSettings: Sendable, Equatable, Codable {
    public var metadata: [String: String]?
    public var instructions: String?
    public var strictJsonSchema: Bool?

    public init(metadata: [String: String]? = nil, instructions: String? = nil, strictJsonSchema: Bool? = nil) {
        self.metadata = metadata
        self.instructions = instructions
        self.strictJsonSchema = strictJsonSchema
    }
}

struct HuggingFaceLanguageModelResponsesOptions: Sendable, Decodable {
    let metadata: [String: String]?
    let instructions: String?
    let strictJsonSchema: Bool?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case metadata, instructions, strictJsonSchema, reasoningEffort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.contains(.metadata) ? container.decode([String: String].self, forKey: .metadata) : nil
        instructions = try container.contains(.instructions) ? container.decode(String.self, forKey: .instructions) : nil
        strictJsonSchema = try container.contains(.strictJsonSchema) ? container.decode(Bool.self, forKey: .strictJsonSchema) : nil
        reasoningEffort = try container.contains(.reasoningEffort) ? container.decode(String.self, forKey: .reasoningEffort) : nil
    }
}

let huggingfaceLanguageModelResponsesOptions = FlexibleSchema(
    Schema<HuggingFaceLanguageModelResponsesOptions>.codable(
        HuggingFaceLanguageModelResponsesOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
