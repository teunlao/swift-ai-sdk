import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICodeInterpreterInput: Codable, Sendable, Equatable {
    public let code: String?
    public let containerId: String

    enum CodingKeys: String, CodingKey {
        case code
        case containerId = "container_id"
    }
}

public struct OpenAICodeInterpreterOutput: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public let type: String
        public let logs: String?
        public let url: String?
    }

    public let outputs: [Item]?
}

public enum OpenAICodeInterpreterContainer: Sendable, Equatable {
    case string(String)
    case auto(fileIds: [String]?)
}

public struct OpenAICodeInterpreterArgs: Sendable, Equatable {
    public let container: OpenAICodeInterpreterContainer?

    public init(container: OpenAICodeInterpreterContainer? = nil) {
        self.container = container
    }
}

private let codeInterpreterInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("container_id")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "code": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "container_id": .object([
            "type": .string("string")
        ])
    ])
])

private let codeInterpreterOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "outputs": .object([
            "type": .array([.string("array"), .string("null")]),
            "items": .object([
                "type": .string("object"),
                "required": .array([.string("type")]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "type": .object([
                        "type": .string("string"),
                        "enum": .array([JSONValue.string("logs"), JSONValue.string("image")])
                    ]),
                    "logs": .object([
                        "type": .array([.string("string"), .string("null")])
                    ]),
                    "url": .object([
                        "type": .array([.string("string"), .string("null")])
                    ])
                ])
            ])
        ])
    ])
])

private let codeInterpreterArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "container": .object([
            "type": .array([.string("string"), .string("object"), .string("null")]),
            "properties": .object([
                "fileIds": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("string")])
                ])
            ]),
            "additionalProperties": .bool(false)
        ])
    ])
])

public let openaiCodeInterpreterInputSchema = FlexibleSchema(
    Schema.codable(OpenAICodeInterpreterInput.self, jsonSchema: codeInterpreterInputJSONSchema)
)

public let openaiCodeInterpreterOutputSchema = FlexibleSchema(
    Schema.codable(OpenAICodeInterpreterOutput.self, jsonSchema: codeInterpreterOutputJSONSchema)
)

public let openaiCodeInterpreterArgsSchema = FlexibleSchema<OpenAICodeInterpreterArgs>(
    Schema(
        jsonSchemaResolver: { codeInterpreterArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "expected object"))
                    return .failure(error: error)
                }

                if let containerValue = dict["container"] {
                    switch containerValue {
                    case .null:
                        break
                    case .string:
                        break
                    case .object(let containerObject):
                        if let fileIds = containerObject["fileIds"], fileIds != .null {
                            guard case .array(let array) = fileIds else {
                                let error = TypeValidationError.wrap(value: fileIds, cause: SchemaValidationIssuesError(vendor: "openai", issues: "fileIds must be array"))
                                return .failure(error: error)
                            }
                            for element in array {
                                guard case .string = element else {
                                    let error = TypeValidationError.wrap(value: element, cause: SchemaValidationIssuesError(vendor: "openai", issues: "fileIds must be strings"))
                                    return .failure(error: error)
                                }
                            }
                        }
                    default:
                        let error = TypeValidationError.wrap(value: containerValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "invalid container"))
                        return .failure(error: error)
                    }
                }

                let args = try parseCodeInterpreterArgs(dict: dict)
                return .success(value: args)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

private func parseCodeInterpreterArgs(dict: [String: JSONValue]) throws -> OpenAICodeInterpreterArgs {
    guard let container = dict["container"], container != .null else {
        return OpenAICodeInterpreterArgs(container: nil)
    }

    switch container {
    case .string(let value):
        return OpenAICodeInterpreterArgs(container: .string(value))
    case .object(let object):
        let fileIds: [String]?
        if let rawFileIds = object["fileIds"], rawFileIds != .null {
            guard case .array(let array) = rawFileIds else {
                throw TypeValidationError.wrap(value: rawFileIds, cause: SchemaValidationIssuesError(vendor: "openai", issues: "fileIds must be array"))
            }
            fileIds = try array.map { element -> String in
                guard case .string(let stringValue) = element else {
                    throw TypeValidationError.wrap(value: element, cause: SchemaValidationIssuesError(vendor: "openai", issues: "fileIds must be strings"))
                }
                return stringValue
            }
        } else {
            fileIds = nil
        }
        return OpenAICodeInterpreterArgs(container: .auto(fileIds: fileIds))
    default:
        throw TypeValidationError.wrap(value: container, cause: SchemaValidationIssuesError(vendor: "openai", issues: "invalid container"))
    }
}

public let openaiCodeInterpreterTool = createProviderDefinedToolFactoryWithOutputSchema(
    id: "openai.code_interpreter",
    name: "code_interpreter",
    inputSchema: FlexibleSchema(jsonSchema(codeInterpreterInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(codeInterpreterOutputJSONSchema))
)
