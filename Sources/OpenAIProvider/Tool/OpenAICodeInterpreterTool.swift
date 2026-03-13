import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICodeInterpreterInput: Codable, Sendable, Equatable {
    public let code: String?
    public let containerId: String
}

public struct OpenAICodeInterpreterOutput: Codable, Sendable, Equatable {
    public enum Item: Codable, Sendable, Equatable {
        case logs(logs: String)
        case image(url: String)

        private enum CodingKeys: String, CodingKey {
            case type
            case logs
            case url
        }

        public var type: String {
            switch self {
            case .logs:
                return "logs"
            case .image:
                return "image"
            }
        }

        public var logs: String? {
            guard case .logs(let logs) = self else { return nil }
            return logs
        }

        public var url: String? {
            guard case .image(let url) = self else { return nil }
            return url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "logs":
                if container.contains(.url) {
                    throw DecodingError.dataCorruptedError(
                        forKey: .url,
                        in: container,
                        debugDescription: "logs output must not contain url"
                    )
                }
                self = .logs(logs: try container.decode(String.self, forKey: .logs))

            case "image":
                if container.contains(.logs) {
                    throw DecodingError.dataCorruptedError(
                        forKey: .logs,
                        in: container,
                        debugDescription: "image output must not contain logs"
                    )
                }
                self = .image(url: try container.decode(String.self, forKey: .url))

            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown code interpreter output type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .logs(let logs):
                try container.encode("logs", forKey: .type)
                try container.encode(logs, forKey: .logs)
            case .image(let url):
                try container.encode("image", forKey: .type)
                try container.encode(url, forKey: .url)
            }
        }
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
    "required": .array([.string("containerId")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "code": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "containerId": .object([
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
                "oneOf": .array([
                    .object([
                        "type": .string("object"),
                        "required": .array([.string("type"), .string("logs")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("logs")])
                            ]),
                            "logs": .object([
                                "type": .string("string")
                            ])
                        ])
                    ]),
                    .object([
                        "type": .string("object"),
                        "required": .array([.string("type"), .string("url")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("image")])
                            ]),
                            "url": .object([
                                "type": .string("string")
                            ])
                        ])
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

private func encodeCodeInterpreterArgs(_ args: OpenAICodeInterpreterArgs) -> [String: JSONValue] {
    guard let container = args.container else { return [:] }
    switch container {
    case .string(let value):
        return ["container": .string(value)]
    case .auto(let fileIds):
        var payload: [String: JSONValue] = ["type": .string("auto")]
        if let fileIds {
            payload["file_ids"] = .array(fileIds.map(JSONValue.string))
        }
        return ["container": .object(payload)]
    }
}

public let openaiCodeInterpreterToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "openai.code_interpreter",
    name: "code_interpreter",
    inputSchema: FlexibleSchema(jsonSchema(codeInterpreterInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(codeInterpreterOutputJSONSchema))
) { (args: OpenAICodeInterpreterArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()
    options.args = encodeCodeInterpreterArgs(args)
    return options
}
