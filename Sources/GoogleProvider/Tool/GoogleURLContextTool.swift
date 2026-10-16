import Foundation
import AISDKProvider
import AISDKProviderUtils

private let googleURLContextInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false)
        ])
    )
)

public let googleURLContextToolFactory = createProviderExecutedToolFactory(
    id: "google.url_context",
    name: "url_context",
    inputSchema: googleURLContextInputSchema,
    outputSchema: googleURLContextInputSchema
)

@discardableResult
public func googleURLContextTool() -> Tool {
    googleURLContextToolFactory(ProviderExecutedToolFactoryOptions(args: [:]))
}
