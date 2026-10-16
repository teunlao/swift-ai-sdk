import Foundation
import AISDKProvider
import AISDKProviderUtils

private let googleEnterpriseWebSearchInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ])
    )
)

public let googleEnterpriseWebSearchToolFactory = createProviderExecutedToolFactory(
    id: "google.enterprise_web_search",
    name: "enterprise_web_search",
    inputSchema: googleEnterpriseWebSearchInputSchema,
    outputSchema: googleEnterpriseWebSearchInputSchema
)

@discardableResult
public func googleEnterpriseWebSearchTool() -> Tool {
    googleEnterpriseWebSearchToolFactory(ProviderExecutedToolFactoryOptions(args: [:]))
}

