import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenAIToolSearchExecution: String, Sendable, Equatable {
    case server
    case client
}

public struct OpenAIToolSearchArgs: Sendable, Equatable {
    public let execution: OpenAIToolSearchExecution?
    public let description: String?
    public let parameters: JSONValue?

    public init(
        execution: OpenAIToolSearchExecution? = nil,
        description: String? = nil,
        parameters: JSONValue? = nil
    ) {
        self.execution = execution
        self.description = description
        self.parameters = parameters
    }
}

struct OpenAIToolSearchInput: Sendable, Equatable {
    let arguments: JSONValue?
    let callId: String?
}

struct OpenAIToolSearchOutput: Sendable, Equatable {
    let tools: [JSONValue]
}

private let toolSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "execution": .object([
            "type": .string("string"),
            "enum": .array([.string("server"), .string("client")])
        ]),
        "description": .object([
            "type": .string("string")
        ]),
        "parameters": .object([
            "type": .string("object")
        ])
    ])
])

private let toolSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "arguments": .bool(true),
        "call_id": .object([
            "type": .array([.string("string"), .string("null")])
        ])
    ])
])

private let toolSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("tools")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "tools": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "additionalProperties": .bool(true)
            ])
        ])
    ])
])

public let openaiToolSearchArgsSchema = FlexibleSchema<OpenAIToolSearchArgs>(
    Schema(
        jsonSchemaResolver: { toolSearchArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let execution: OpenAIToolSearchExecution?
                if let rawExecution = dict["execution"], rawExecution != .null {
                    guard case .string(let value) = rawExecution,
                          let parsed = OpenAIToolSearchExecution(rawValue: value) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "execution must be 'server' or 'client'")
                        return .failure(error: TypeValidationError.wrap(value: rawExecution, cause: error))
                    }
                    execution = parsed
                } else {
                    execution = nil
                }

                let description: String?
                if let rawDescription = dict["description"], rawDescription != .null {
                    guard case .string(let value) = rawDescription else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "description must be a string")
                        return .failure(error: TypeValidationError.wrap(value: rawDescription, cause: error))
                    }
                    description = value
                } else {
                    description = nil
                }

                let parameters: JSONValue?
                if let rawParameters = dict["parameters"], rawParameters != .null {
                    guard case .object = rawParameters else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "parameters must be an object")
                        return .failure(error: TypeValidationError.wrap(value: rawParameters, cause: error))
                    }
                    parameters = rawParameters
                } else {
                    parameters = nil
                }

                return .success(value: OpenAIToolSearchArgs(
                    execution: execution,
                    description: description,
                    parameters: parameters
                ))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

let openaiToolSearchInputSchema = FlexibleSchema<OpenAIToolSearchInput>(
    Schema(
        jsonSchemaResolver: { toolSearchInputJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let callId: String?
                if let rawCallId = dict["call_id"], rawCallId != .null {
                    guard case .string(let value) = rawCallId else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "call_id must be a string or null")
                        return .failure(error: TypeValidationError.wrap(value: rawCallId, cause: error))
                    }
                    callId = value
                } else {
                    callId = nil
                }

                return .success(value: OpenAIToolSearchInput(
                    arguments: dict["arguments"],
                    callId: callId
                ))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

let openaiToolSearchOutputSchema = FlexibleSchema<OpenAIToolSearchOutput>(
    Schema(
        jsonSchemaResolver: { toolSearchOutputJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json,
                      case .array(let tools)? = dict["tools"] else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "tools must be an array")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                for tool in tools {
                    guard case .object = tool else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "tools must contain objects")
                        return .failure(error: TypeValidationError.wrap(value: tool, cause: error))
                    }
                }

                return .success(value: OpenAIToolSearchOutput(tools: tools))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

public let openaiToolSearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "openai.tool_search",
    name: "tool_search",
    inputSchema: FlexibleSchema(jsonSchema(toolSearchInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(toolSearchOutputJSONSchema))
) { (args: OpenAIToolSearchArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()
    options.args = encodeOpenAIToolSearchArgs(args)
    return options
}

private func encodeOpenAIToolSearchArgs(_ args: OpenAIToolSearchArgs) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [:]

    if let execution = args.execution {
        payload["execution"] = .string(execution.rawValue)
    }
    if let description = args.description {
        payload["description"] = .string(description)
    }
    if let parameters = args.parameters {
        payload["parameters"] = parameters
    }

    return payload
}
