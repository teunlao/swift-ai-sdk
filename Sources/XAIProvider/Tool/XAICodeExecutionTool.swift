import Foundation
import AISDKProvider
import AISDKProviderUtils

private let emptyObjectJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([:])
])

private let codeExecutionOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("output")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "output": .object(["type": .string("string")]),
        "error": .object(["type": .string("string")])
    ])
])

public let xaiCodeExecutionToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.code_execution",
    name: "code_execution",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(codeExecutionOutputJSONSchema))
)
