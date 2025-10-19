import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicBashOptions: Sendable, Equatable {
    public var command: String?
    public var restart: Bool?

    public init(command: String? = nil, restart: Bool? = nil) {
        self.command = command
        self.restart = restart
    }
}

private let anthropicBashInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object(["type": .array([.string("string"), .string("null")])]),
                "restart": .object(["type": .array([.string("boolean"), .string("null")])])
            ]),
            "additionalProperties": .bool(true)
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
public func anthropicBash20241022(_ options: AnthropicBashOptions = .init()) -> Tool {
    anthropicBash20241022Factory(.init(args: anthropicBashArgs(options)))
}

@discardableResult
public func anthropicBash20250124(_ options: AnthropicBashOptions = .init()) -> Tool {
    anthropicBash20250124Factory(.init(args: anthropicBashArgs(options)))
}

private func anthropicBashArgs(_ options: AnthropicBashOptions) -> [String: JSONValue] {
    var args: [String: JSONValue] = [:]
    if let command = options.command {
        args["command"] = .string(command)
    }
    if let restart = options.restart {
        args["restart"] = .bool(restart)
    }
    return args
}
