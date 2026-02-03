import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Prepares tools and tool choice for a model call.

 Port of `@ai-sdk/ai/src/prompt/prepare-tools-and-tool-choice.ts`.
 */
public func prepareToolsAndToolChoice(
    tools: [String: Tool]?,
    toolChoice: ToolChoice?,
    activeTools: [String]?
) async throws -> (
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) {
    // Check if tools dictionary is non-empty
    guard let tools, !tools.isEmpty else {
        return (tools: nil, toolChoice: nil)
    }

    // Filter tools by activeTools if provided
    // Sort by key to ensure deterministic order (matching JS Object.entries insertion order behavior)
    let filteredTools: [(key: String, value: Tool)]
    if let activeTools {
        filteredTools = tools.filter { activeTools.contains($0.key) }.sorted { $0.key < $1.key }
    } else {
        filteredTools = tools.sorted { $0.key < $1.key }
    }

    // Convert tools to LanguageModelV3 format
    var languageModelTools: [LanguageModelV3Tool] = []

    for (name, tool) in filteredTools {
        let toolType = tool.type

        switch toolType {
        case nil, .function, .dynamic:
            // Function tool (nil, 'function', or 'dynamic' all map to function)
            let jsonSchema = try await tool.inputSchema.resolve().jsonSchema()

            // Convert providerOptions to SharedV3ProviderOptions format
            // Tool.providerOptions is [String: JSONValue] where values are already nested objects
            // SharedV3ProviderOptions expects [String: [String: JSONValue]]
            // Cast each JSONValue to the expected nested dictionary structure
            let providerOptions: SharedV3ProviderOptions? = tool.providerOptions.map { options in
                options.compactMapValues { value in
                    // Each value should already be a nested object (e.g., { "aSetting": "aValue" })
                    if case .object(let nestedDict) = value {
                        return nestedDict
                    }
                    return nil
                }
            }

            let functionTool = LanguageModelV3FunctionTool(
                name: name,
                inputSchema: jsonSchema,
                inputExamples: tool.inputExamples,
                description: tool.description,
                strict: tool.strict,
                providerOptions: providerOptions
            )
            languageModelTools.append(.function(functionTool))

        case .provider:
            // Provider tool
            // Use dictionary key 'name' as tool name, matching TypeScript behavior (line 61 in upstream)
            guard let id = tool.id else {
                throw InvalidArgumentError(
                    parameter: "tools[\(name)]",
                    value: JSONValue.string(String(describing: tool)),
                    message: "Provider tool must have 'id' field"
                )
            }

            let providerTool = LanguageModelV3ProviderTool(
                id: id,
                name: name,  // Use dictionary key, not tool.name field
                args: tool.args ?? [:]
            )
            languageModelTools.append(.provider(providerTool))
        }
    }

    // Convert toolChoice to LanguageModelV3ToolChoice
    let convertedToolChoice: LanguageModelV3ToolChoice
    if let toolChoice {
        switch toolChoice {
        case .auto:
            convertedToolChoice = .auto
        case .none:
            convertedToolChoice = .none
        case .required:
            convertedToolChoice = .required
        case .tool(let toolName):
            convertedToolChoice = .tool(toolName: toolName)
        }
    } else {
        // Default to 'auto' when toolChoice is nil
        convertedToolChoice = .auto
    }

    return (tools: languageModelTools, toolChoice: convertedToolChoice)
}

/// Tool choice for model generation.
///
/// Port of `@ai-sdk/ai/src/types/language-model.ts` ToolChoice type.
public enum ToolChoice: Sendable, Equatable {
    /// The model can choose whether and which tools to call (default).
    case auto

    /// The model must not call tools.
    case none

    /// The model must call a tool (any tool).
    case required

    /// The model must call the specified tool.
    case tool(toolName: String)
}
