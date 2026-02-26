import Foundation
import AISDKProvider
import AISDKProviderUtils

private let emptyObjectJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([:])
])

private let viewImageOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("description")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "description": .object(["type": .string("string")]),
        "objects": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ])
    ])
])

public let xaiViewImageToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.view_image",
    name: "view_image",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(viewImageOutputJSONSchema))
)

