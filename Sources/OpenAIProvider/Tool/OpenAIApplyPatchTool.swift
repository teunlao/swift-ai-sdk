import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenAIApplyPatchOperation: Sendable, Equatable, Codable {
    case createFile(path: String, diff: String)
    case deleteFile(path: String)
    case updateFile(path: String, diff: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case diff
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let path = try container.decode(String.self, forKey: .path)

        switch type {
        case "create_file":
            let diff = try container.decode(String.self, forKey: .diff)
            self = .createFile(path: path, diff: diff)
        case "delete_file":
            self = .deleteFile(path: path)
        case "update_file":
            let diff = try container.decode(String.self, forKey: .diff)
            self = .updateFile(path: path, diff: diff)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown apply_patch operation type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .createFile(path, diff):
            try container.encode("create_file", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(diff, forKey: .diff)
        case let .deleteFile(path):
            try container.encode("delete_file", forKey: .type)
            try container.encode(path, forKey: .path)
        case let .updateFile(path, diff):
            try container.encode("update_file", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(diff, forKey: .diff)
        }
    }
}

public struct OpenAIApplyPatchInput: Codable, Sendable, Equatable {
    public let callId: String
    public let operation: OpenAIApplyPatchOperation
}

public struct OpenAIApplyPatchOutput: Codable, Sendable, Equatable {
    public let status: String
    public let output: String?
}

private let applyPatchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("callId"), .string("operation")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "callId": .object([
            "type": .string("string")
        ]),
        "operation": .object([
            "type": .string("object"),
            "required": .array([.string("type"), .string("path")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object([
                    "type": .string("string"),
                    "enum": .array([.string("create_file"), .string("delete_file"), .string("update_file")])
                ]),
                "path": .object([
                    "type": .string("string")
                ]),
                "diff": .object([
                    "type": .array([.string("string"), .string("null")])
                ])
            ])
        ])
    ])
])

private let applyPatchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("status")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "status": .object([
            "type": .string("string"),
            "enum": .array([.string("completed"), .string("failed")])
        ]),
        "output": .object([
            "type": .array([.string("string"), .string("null")])
        ])
    ])
])

public let openaiApplyPatchInputSchema = FlexibleSchema(
    Schema.codable(OpenAIApplyPatchInput.self, jsonSchema: applyPatchInputJSONSchema)
)

public let openaiApplyPatchOutputSchema = FlexibleSchema(
    Schema.codable(OpenAIApplyPatchOutput.self, jsonSchema: applyPatchOutputJSONSchema)
)

public let openaiApplyPatchTool = createProviderDefinedToolFactoryWithOutputSchema(
    id: "openai.apply_patch",
    name: "apply_patch",
    inputSchema: FlexibleSchema(jsonSchema(applyPatchInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(applyPatchOutputJSONSchema))
)

