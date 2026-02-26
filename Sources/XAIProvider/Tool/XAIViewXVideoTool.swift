import Foundation
import AISDKProvider
import AISDKProviderUtils

private let emptyObjectJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([:])
])

private let viewXVideoOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("description")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "transcript": .object(["type": .string("string")]),
        "description": .object(["type": .string("string")]),
        "duration": .object(["type": .string("number")])
    ])
])

public let xaiViewXVideoToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.view_x_video",
    name: "view_x_video",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(viewXVideoOutputJSONSchema))
)

