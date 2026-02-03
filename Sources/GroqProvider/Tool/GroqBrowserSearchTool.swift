import Foundation
import AISDKProvider
import AISDKProviderUtils

public let groqBrowserSearchToolFactory = createProviderToolFactory(
    id: "groq.browser_search",
    name: "browser_search",
    inputSchema: FlexibleSchema(jsonSchema(.object([
        "type": .string("object"),
        "additionalProperties": .bool(false)
    ])))
)

@discardableResult
public func groqBrowserSearchTool() -> Tool {
    groqBrowserSearchToolFactory(ProviderToolFactoryOptions(args: [:]))
}
