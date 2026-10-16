import Foundation
import AISDKProvider
import AISDKProviderUtils

private let anthropicBashInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object(["type": .string("string")]),
                "restart": .object(["type": .string("boolean")])
            ]),
            "additionalProperties": .bool(false)
        ])
    )
)

private let anthropicBash20241022Factory = createProviderDefinedToolFactory(
    id: "anthropic.bash_20241022",
    name: "bash",
    inputSchema: anthropicBashInputSchema
)

private let anthropicBash20250124Factory = createProviderDefinedToolFactory(
    id: "anthropic.bash_20250124",
    name: "bash",
    inputSchema: anthropicBashInputSchema
)

@discardableResult
public func anthropicBash20241022(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
    anthropicBash20241022Factory(options)
}

@discardableResult
public func anthropicBash20250124(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool {
    anthropicBash20250124Factory(options)
}
