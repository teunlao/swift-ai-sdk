import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/huggingface-responses-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct HuggingFaceResponsesProviderOptions: Sendable, Equatable, Codable {
    public var metadata: [String: String]?
    public var instructions: String?
    public var strictJsonSchema: Bool?

    public init(metadata: [String: String]? = nil, instructions: String? = nil, strictJsonSchema: Bool? = nil) {
        self.metadata = metadata
        self.instructions = instructions
        self.strictJsonSchema = strictJsonSchema
    }
}

private let huggingfaceResponsesProviderOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "metadata": .object([
            "type": .string("object"),
            "additionalProperties": .object(["type": .string("string")])
        ]),
        "instructions": .object(["type": .string("string")]),
        "strictJsonSchema": .object(["type": .string("boolean")])
    ])
])

public let huggingfaceResponsesProviderOptionsSchema = FlexibleSchema(
    Schema<HuggingFaceResponsesProviderOptions>.codable(
        HuggingFaceResponsesProviderOptions.self,
        jsonSchema: huggingfaceResponsesProviderOptionsSchemaJSON
    )
)
