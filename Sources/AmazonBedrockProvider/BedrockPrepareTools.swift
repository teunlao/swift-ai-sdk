import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-prepare-tools.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

struct BedrockPreparedTools: Sendable {
    let toolConfig: [String: JSONValue]
    let additionalTools: [String: JSONValue]?
    let betas: Set<String>
    let warnings: [SharedV4Warning]
}

func prepareBedrockTools(
    tools: [LanguageModelV4Tool]?,
    toolChoice: LanguageModelV4ToolChoice?,
    modelId: String,
    modelFamily: BedrockChatModelSettings.ModelFamily? = nil,
    reasoningBudgetTokens: Int? = nil,
    disableParallelToolUse: Bool? = nil,
    rejectsForcedToolUse: Bool = false
) async throws -> BedrockPreparedTools {
    var warnings: [SharedV4Warning] = []
    var betas: Set<String> = []
    var additionalTools: [String: JSONValue]? = nil
    var bedrockTools: [JSONValue] = []

    guard let tools, !tools.isEmpty else {
        return BedrockPreparedTools(toolConfig: [:], additionalTools: nil, betas: [], warnings: [])
    }

    // Filter unsupported provider-defined tools (web search)
    let filteredTools: [LanguageModelV4Tool] = tools.compactMap { tool in
        if case .provider(let providerTool) = tool,
           ["anthropic.web_search_20250305", "anthropic.web_search_20260318", "anthropic.web_fetch_20260318"].contains(providerTool.id) {
            warnings.append(
                .unsupported(
                    feature: "\(providerTool.id.dropFirst("anthropic.".count)) tool",
                    details: "The \(providerTool.id.dropFirst("anthropic.".count)) tool is not supported on Amazon Bedrock."
                )
            )
            return nil
        }
        return tool
    }

    if filteredTools.isEmpty {
        return BedrockPreparedTools(toolConfig: [:], additionalTools: nil, betas: betas, warnings: warnings)
    }

    let isAnthropicModel = isBedrockAnthropicModel(modelId, modelFamily: modelFamily, reasoningBudgetTokens: reasoningBudgetTokens)
    let rejectsForcedChoice = isAnthropicModel && rejectsForcedToolUse && (toolChoice == .required || { if case .tool = toolChoice { return true }; return false }())
    var preparedToolChoice = toolChoice
    if rejectsForcedChoice { preparedToolChoice = .auto }

    var providerTools: [LanguageModelV4ProviderTool] = []
    var providerToolWrappers: [LanguageModelV4Tool] = []
    var functionTools: [LanguageModelV4FunctionTool] = []

    for tool in filteredTools {
        switch tool {
        case .provider(let providerTool):
            providerTools.append(providerTool)
            providerToolWrappers.append(tool)
        case .function(let functionTool):
            functionTools.append(functionTool)
        }
    }

    let providerToolsForRequest = providerTools.filter { tool in
        if rejectsForcedChoice, case .tool(let name) = toolChoice { return tool.name == name }
        return true
    }
    let usingAnthropicTools = isAnthropicModel && !providerToolsForRequest.isEmpty

    if usingAnthropicTools {
        let prepared = try await prepareAnthropicTools(
            tools: providerToolWrappers,
            toolChoice: toolChoice,
            disableParallelToolUse: disableParallelToolUse,
            supportsStructuredOutput: false,
            supportsStrictTools: false,
            rejectsForcedToolUse: rejectsForcedToolUse
        )
        warnings.append(contentsOf: prepared.warnings)
        betas.formUnion(prepared.betas)
        if let toolChoiceJSON = prepared.toolChoice {
            additionalTools = ["tool_choice": toolChoiceJSON]
        }

        for providerTool in providerToolsForRequest {
            if let bedrockTool = try await makeAnthropicBedrockTool(providerTool) {
                bedrockTools.append(bedrockTool)
            } else {
                warnings.append(.unsupported(feature: "tool \(providerTool.id)", details: nil))
            }
        }
    } else {
        // Provider-defined tools are unsupported for non-Anthropic models
        for providerTool in providerToolsForRequest {
            warnings.append(.unsupported(feature: "tool \(providerTool.id)", details: nil))
        }
    }

    if !usingAnthropicTools && rejectsForcedChoice {
        let details: String
        if case .tool(let name) = toolChoice {
            details = "toolChoice 'tool' is not supported by this model because it rejects forced tool use. Only the '\(name)' tool is sent with 'auto' tool choice. Instruct the model to use the tool in the prompt and verify that a tool call was made."
        } else {
            details = "toolChoice 'required' is not supported by this model because it rejects forced tool use. Using 'auto' instead. Instruct the model to use a tool in the prompt and verify that a tool call was made."
        }
        warnings.append(.unsupported(feature: "toolChoice", details: details))
    }
    for functionTool in functionTools {
        if case .tool(let name) = toolChoice, functionTool.name != name { continue }
        var toolSpec: [String: JSONValue] = [
            "name": .string(functionTool.name),
            "inputSchema": .object(["json": functionTool.inputSchema])
        ]
        if let description = functionTool.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toolSpec["description"] = .string(description)
        }
        let supportsStrict = bedrockSupportsStrictTools(modelId)
        let compatible = functionTool.strict != true || isStrictBedrockSchemaCompatible(functionTool.inputSchema)
        if let strict = functionTool.strict, supportsStrict && compatible {
            toolSpec["strict"] = .bool(strict)
        } else if functionTool.strict == true {
            warnings.append(.unsupported(feature: "strict", details: supportsStrict ? "Tool '\(functionTool.name)' has strict: true, but Amazon Bedrock requires every object in a strict tool schema to set additionalProperties: false. The strict property will be ignored." : "Tool '\(functionTool.name)' has strict: true, but strict mode is not supported by this model on Amazon Bedrock. The strict property will be ignored."))
        }
        bedrockTools.append(.object(["toolSpec": .object(toolSpec)]))
    }

    if isAnthropicModel && !usingAnthropicTools && disableParallelToolUse == true && !bedrockTools.isEmpty && preparedToolChoice != LanguageModelV4ToolChoice.none {
        var choice: [String: JSONValue] = ["type": .string("auto"), "disable_parallel_tool_use": .bool(true)]
        if preparedToolChoice == .required { choice["type"] = .string("any") }
        if case .tool(let name) = preparedToolChoice { choice["type"] = .string("tool"); choice["name"] = .string(name) }
        additionalTools = ["tool_choice": .object(choice)]
    }
    var toolChoiceJSON: JSONValue? = nil
    if !usingAnthropicTools, additionalTools?["tool_choice"] == nil, !bedrockTools.isEmpty, let toolChoice = preparedToolChoice {
        switch toolChoice {
        case .auto:
            toolChoiceJSON = .object(["auto": .object([:])])
        case .required:
            toolChoiceJSON = .object(["any": .object([:])])
        case .none:
            bedrockTools.removeAll()
            toolChoiceJSON = nil
        case .tool(let toolName):
            toolChoiceJSON = .object(["tool": .object(["name": .string(toolName)])])
        }
    }

    var toolConfig: [String: JSONValue] = [:]
    if !bedrockTools.isEmpty {
        toolConfig["tools"] = .array(bedrockTools)
    }
    if let toolChoiceJSON, !usingAnthropicTools {
        toolConfig["toolChoice"] = toolChoiceJSON
    }

    return BedrockPreparedTools(toolConfig: toolConfig, additionalTools: additionalTools, betas: betas, warnings: warnings)
}

// MARK: - Anthropic Tool Helpers

private func makeAnthropicBedrockTool(
    _ tool: LanguageModelV4ProviderTool
) async throws -> JSONValue? {
    let definition: Tool

    switch tool.id {
    case "anthropic.advisor_20260301":
        let args = try JSONDecoder().decode(AnthropicAdvisor20260301Options.self, from: JSONEncoder().encode(tool.args))
        definition = anthropicAdvisor20260301(args)
    case "anthropic.computer_toolset_20260801":
        definition = anthropicComputerToolset20260801()
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
    case "anthropic.computer_20251124":
        definition = anthropicComputer20251124(.init(displayWidthPx: 0, displayHeightPx: 0))
    case "anthropic.code_execution_20250522":
        definition = anthropicCodeExecution20250522()
    case "anthropic.code_execution_20250825":
        definition = anthropicCodeExecution20250825()
    case "anthropic.code_execution_20260120":
        definition = anthropicCodeExecution20260120()
    case "anthropic.memory_20250818":
        definition = anthropicMemory20250818()
    case "anthropic.tool_search_regex_20251119":
        definition = anthropicToolSearchRegex20251119()
    case "anthropic.tool_search_bm25_20251119":
        definition = anthropicToolSearchBm2520251119()
    case "anthropic.web_fetch_20250910":
        definition = anthropicWebFetch20250910(.init())
    case "anthropic.web_fetch_20260209":
        definition = anthropicWebFetch20260209(.init())
    case "anthropic.web_search_20260209":
        definition = anthropicWebSearch20260209(.init())
    default:
        return nil
    }

    let schema = try await asSchema(definition.inputSchema).jsonSchema()
    let name = tool.name

    let toolSpec: [String: JSONValue] = [
        "name": .string(name),
        "inputSchema": .object(["json": schema])
    ]

    return .object(["toolSpec": .object(toolSpec)])
}

private func isStrictBedrockSchemaCompatible(_ schema: JSONValue) -> Bool {
    guard case .object(let object) = schema else { return true }
    let isObject = object["type"] == .string("object") || { if case .array(let types)? = object["type"] { return types.contains(.string("object")) }; return false }()
    if isObject && object["additionalProperties"] != .bool(false) { return false }
    for key in ["properties", "patternProperties", "definitions", "$defs", "dependencies"] {
        if case .object(let values)? = object[key], values.values.contains(where: { !isStrictBedrockSchemaCompatible($0) }) { return false }
    }
    for key in ["propertyNames", "contains", "not", "if", "then", "else"] {
        if let value = object[key], !isStrictBedrockSchemaCompatible(value) { return false }
    }
    for key in ["items", "anyOf", "allOf", "oneOf"] {
        if case .array(let values)? = object[key] {
            if values.contains(where: { !isStrictBedrockSchemaCompatible($0) }) { return false }
        } else if let value = object[key], !isStrictBedrockSchemaCompatible(value) { return false }
    }
    return true
}
