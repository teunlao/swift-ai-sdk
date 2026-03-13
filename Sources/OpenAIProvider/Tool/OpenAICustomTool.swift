import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenAICustomToolFormat: Sendable, Equatable {
    public enum GrammarSyntax: String, Sendable, Equatable {
        case regex
        case lark
    }

    case grammar(syntax: GrammarSyntax, definition: String)
    case text
}

public struct OpenAICustomToolArgs: Sendable, Equatable {
    public let name: String
    public let description: String?
    public let format: OpenAICustomToolFormat?

    public init(
        name: String,
        description: String? = nil,
        format: OpenAICustomToolFormat? = nil
    ) {
        self.name = name
        self.description = description
        self.format = format
    }
}

private let customArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "required": .array([.string("name")]),
    "properties": .object([
        "name": .object([
            "type": .string("string")
        ]),
        "description": .object([
            "type": .string("string")
        ]),
        "format": .object([
            "anyOf": .array([
                .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("type"), .string("syntax"), .string("definition")]),
                    "properties": .object([
                        "type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("grammar")])
                        ]),
                        "syntax": .object([
                            "type": .string("string"),
                            "enum": .array([.string("regex"), .string("lark")])
                        ]),
                        "definition": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("type")]),
                    "properties": .object([
                        "type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("text")])
                        ])
                    ])
                ])
            ])
        ])
    ])
])

private let customInputJSONSchema: JSONValue = .object([
    "type": .string("string")
])

public let openaiCustomArgsSchema = FlexibleSchema<OpenAICustomToolArgs>(
    Schema(
        jsonSchemaResolver: { customArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                guard case .string(let name) = dict["name"] else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "name must be a string")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let description: String?
                if let rawDescription = dict["description"] {
                    guard case .string(let value) = rawDescription else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "description must be a string")
                        return .failure(error: TypeValidationError.wrap(value: rawDescription, cause: error))
                    }
                    description = value
                } else {
                    description = nil
                }

                let format: OpenAICustomToolFormat?
                if let rawFormat = dict["format"] {
                    guard case .object(let formatObject) = rawFormat,
                          case .string(let rawType)? = formatObject["type"] else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "format must be an object")
                        return .failure(error: TypeValidationError.wrap(value: rawFormat, cause: error))
                    }

                    switch rawType {
                    case "grammar":
                        guard case .string(let rawSyntax)? = formatObject["syntax"],
                              let syntax = OpenAICustomToolFormat.GrammarSyntax(rawValue: rawSyntax),
                              case .string(let definition)? = formatObject["definition"] else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "grammar format requires syntax and definition")
                            return .failure(error: TypeValidationError.wrap(value: rawFormat, cause: error))
                        }
                        format = .grammar(syntax: syntax, definition: definition)

                    case "text":
                        format = .text

                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "format.type must be 'grammar' or 'text'")
                        return .failure(error: TypeValidationError.wrap(value: rawFormat, cause: error))
                    }
                } else {
                    format = nil
                }

                return .success(value: OpenAICustomToolArgs(
                    name: name,
                    description: description,
                    format: format
                ))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

public let openaiCustomToolFactory = createProviderToolFactory(
    id: "openai.custom",
    name: "custom",
    inputSchema: FlexibleSchema(jsonSchema(customInputJSONSchema))
) { (args: OpenAICustomToolArgs) in
    var options = ProviderToolFactoryOptions()
    options.args = encodeOpenAICustomToolArgs(args)
    return options
}

private func encodeOpenAICustomToolArgs(_ args: OpenAICustomToolArgs) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [
        "name": .string(args.name)
    ]

    if let description = args.description {
        payload["description"] = .string(description)
    }

    if let format = args.format {
        switch format {
        case .grammar(let syntax, let definition):
            payload["format"] = .object([
                "type": .string("grammar"),
                "syntax": .string(syntax.rawValue),
                "definition": .string(definition)
            ])
        case .text:
            payload["format"] = .object([
                "type": .string("text")
            ])
        }
    }

    return payload
}
