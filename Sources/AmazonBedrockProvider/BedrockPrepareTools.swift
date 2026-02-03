import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-prepare-tools.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct BedrockPreparedTools: Sendable {
    let toolConfig: [String: JSONValue]
    let additionalTools: [String: JSONValue]?
    let betas: Set<String>
    let warnings: [SharedV3Warning]
}

func prepareBedrockTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    modelId: String
) async -> BedrockPreparedTools {
    var warnings: [SharedV3Warning] = []
    var betas: Set<String> = []
    var additionalTools: [String: JSONValue]? = nil
    var bedrockTools: [JSONValue] = []

    guard let tools, !tools.isEmpty else {
        return BedrockPreparedTools(toolConfig: [:], additionalTools: nil, betas: [], warnings: [])
    }

    // Filter unsupported provider-defined tools (web search)
    let filteredTools: [LanguageModelV3Tool] = tools.compactMap { tool in
        if case .provider(let providerTool) = tool,
           providerTool.id == "anthropic.web_search_20250305" {
            warnings.append(
                .unsupported(
                    feature: "web_search_20250305 tool",
                    details: "The web_search_20250305 tool is not supported on Amazon Bedrock."
                )
            )
            return nil
        }
        return tool
    }

    if filteredTools.isEmpty {
        return BedrockPreparedTools(toolConfig: [:], additionalTools: nil, betas: betas, warnings: warnings)
    }

    let isAnthropicModel = modelId.contains("anthropic.") || modelId.contains("us.anthropic.")

    var providerTools: [LanguageModelV3ProviderTool] = []
    var providerToolWrappers: [LanguageModelV3Tool] = []
    var functionTools: [LanguageModelV3FunctionTool] = []

    for tool in filteredTools {
        switch tool {
        case .provider(let providerTool):
            providerTools.append(providerTool)
            providerToolWrappers.append(tool)
        case .function(let functionTool):
            functionTools.append(functionTool)
        }
    }

    if isAnthropicModel && !providerTools.isEmpty {
        do {
            let prepared = try await prepareAnthropicTools(
                tools: providerToolWrappers,
                toolChoice: toolChoice,
                disableParallelToolUse: nil
            )
            warnings.append(contentsOf: prepared.warnings)
            betas.formUnion(prepared.betas)
            if let toolChoiceJSON = prepared.toolChoice {
                additionalTools = ["tool_choice": toolChoiceJSON]
            }

            for providerTool in providerTools {
                if let bedrockTool = try await makeAnthropicBedrockTool(providerTool) {
                    bedrockTools.append(bedrockTool)
                } else {
                    warnings.append(.unsupported(feature: "tool \(providerTool.id)", details: nil))
                }
            }
        } catch {
            warnings.append(.other(message: "Failed to prepare Anthropic tools: \(error)"))
        }

        if !functionTools.isEmpty {
            warnings.append(
                .unsupported(
                    feature: "mixing Anthropic provider tools and standard function tools",
                    details: "Mixed Anthropic provider tools and standard function tools are not supported in a single Bedrock call. Only Anthropic tools will be used."
                )
            )
        }

        // Anthropic scenario ignores standard function tools
        functionTools.removeAll()
    } else {
        // Provider-defined tools are unsupported for non-Anthropic models
        for providerTool in providerTools {
            warnings.append(.unsupported(feature: "tool \(providerTool.id)", details: nil))
        }
    }

    for functionTool in functionTools {
        var toolSpec: [String: JSONValue] = [
            "name": .string(functionTool.name),
            "inputSchema": .object(["json": functionTool.inputSchema])
        ]
        if let description = functionTool.description {
            toolSpec["description"] = .string(description)
        }
        bedrockTools.append(.object(["toolSpec": .object(toolSpec)]))
    }

    var toolChoiceJSON: JSONValue? = nil
    if !isAnthropicModel {
        switch toolChoice {
        case .some(.none):
            bedrockTools.removeAll()
            toolChoiceJSON = nil
        case .some(.auto):
            toolChoiceJSON = nil
        case .some(.required):
            toolChoiceJSON = .object(["any": .object([:])])
        case .some(.tool(let toolName)):
            toolChoiceJSON = .object(["tool": .object(["name": .string(toolName)])])
        case Optional<LanguageModelV3ToolChoice>.none:
            break
        }
    }

    var toolConfig: [String: JSONValue] = [:]
    if !bedrockTools.isEmpty {
        toolConfig["tools"] = .array(bedrockTools)
    }
    if let toolChoiceJSON, !isAnthropicModel {
        toolConfig["toolChoice"] = toolChoiceJSON
    }

    return BedrockPreparedTools(toolConfig: toolConfig, additionalTools: additionalTools, betas: betas, warnings: warnings)
}

// MARK: - Anthropic Tool Helpers

private func makeAnthropicBedrockTool(
    _ tool: LanguageModelV3ProviderTool
) async throws -> JSONValue? {
    let definition: Tool

    switch tool.id {
    case "anthropic.bash_20241022":
        definition = anthropicBash20241022()
    case "anthropic.bash_20250124":
        definition = anthropicBash20250124()
    case "anthropic.computer_20241022":
        let options = AnthropicComputerOptions(displayWidthPx: 0, displayHeightPx: 0)
        definition = anthropicComputer20241022(options)
    case "anthropic.computer_20250124":
        let options = AnthropicComputerOptions(displayWidthPx: 0, displayHeightPx: 0)
        definition = anthropicComputer20250124(options)
    case "anthropic.text_editor_20241022":
        definition = anthropicTextEditor20241022()
    case "anthropic.text_editor_20250124":
        definition = anthropicTextEditor20250124()
    case "anthropic.text_editor_20250429":
        definition = anthropicTextEditor20250429()
    case "anthropic.text_editor_20250728":
        definition = anthropicTextEditor20250728(.init())
    case "anthropic.code_execution_20250522":
        definition = anthropicCodeExecution20250522()
    case "anthropic.web_fetch_20250910":
        definition = anthropicWebFetch20250910(.init())
    default:
        return nil
    }

    let schema = try await asSchema(definition.inputSchema).jsonSchema()
    let name = definition.name ?? tool.name

    let toolSpec: [String: JSONValue] = [
        "name": .string(name),
        "inputSchema": .object(["json": schema])
    ]

    return .object(["toolSpec": .object(toolSpec)])
}
