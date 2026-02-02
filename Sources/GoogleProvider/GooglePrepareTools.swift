import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GooglePreparedTools: Sendable {
    let tools: JSONValue?
    let toolConfig: JSONValue?
    let toolWarnings: [LanguageModelV3CallWarning]
}

private func toJSONValue(_ value: Any) -> JSONValue? {
    try? jsonValue(from: value)
}

func prepareGoogleTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    modelId: GoogleGenerativeAIModelId
) -> GooglePreparedTools {
    var warnings: [LanguageModelV3CallWarning] = []

    guard let tools, !tools.isEmpty else {
        return GooglePreparedTools(tools: nil, toolConfig: nil, toolWarnings: warnings)
    }

    let latestIds: Set<String> = [
        "gemini-flash-latest",
        "gemini-flash-lite-latest",
        "gemini-pro-latest"
    ]
    let modelIdString = modelId.rawValue

    let isGemini2 = modelIdString.contains("gemini-2") || latestIds.contains(modelIdString)
    let supportsDynamicRetrieval = modelIdString.contains("gemini-1.5-flash") && !modelIdString.contains("-8b")

    let hasFunctionTools = tools.contains { if case .function = $0 { return true } else { return false } }
    let hasProviderDefinedTools = tools.contains { if case .providerDefined = $0 { return true } else { return false } }

    if hasFunctionTools && hasProviderDefinedTools {
        if let firstFunction = tools.first(where: { if case .function = $0 { return true } else { return false } }) {
            warnings.append(
                .unsupportedTool(
                    tool: firstFunction,
                    details: "Cannot mix function tools with provider-defined tools in the same request. Please use either function tools or provider-defined tools, but not both."
                )
            )
        }
    }

    if hasProviderDefinedTools {
        var googleToolsEntries: [JSONValue] = []

        for tool in tools {
            guard case .providerDefined(let providerTool) = tool else { continue }

            switch providerTool.id {
            case "google.google_search":
                if isGemini2 {
                    googleToolsEntries.append(.object([
                        "googleSearch": .object([:])
                    ]))
                } else if supportsDynamicRetrieval {
                    var config: [String: JSONValue] = [:]
                    if let modeValue = providerTool.args["mode"], case .string(let mode) = modeValue {
                        config["mode"] = .string(mode)
                    }
                    if let thresholdValue = providerTool.args["dynamicThreshold"], case .number(let number) = thresholdValue {
                        config["dynamicThreshold"] = .number(number)
                    }
                    googleToolsEntries.append(.object([
                        "googleSearchRetrieval": .object([
                            "dynamicRetrievalConfig": .object(config)
                        ])
                    ]))
                } else {
                    googleToolsEntries.append(.object([
                        "googleSearchRetrieval": .object([:])
                    ]))
                }

            case "google.url_context":
                if isGemini2 {
                    googleToolsEntries.append(.object([
                        "urlContext": .object([:])
                    ]))
                } else {
                    warnings.append(
                        .unsupportedTool(
                            tool: tool,
                            details: "The URL context tool is not supported with other Gemini models than Gemini 2."
                        )
                    )
                }

            case "google.code_execution":
                if isGemini2 {
                    googleToolsEntries.append(.object([
                        "codeExecution": .object([:])
                    ]))
                } else {
                    warnings.append(
                        .unsupportedTool(
                            tool: tool,
                            details: "The code execution tool is not supported with other Gemini models than Gemini 2."
                        )
                    )
                }

            default:
                warnings.append(.unsupportedTool(tool: tool, details: nil))
            }
        }

        let toolsValue = googleToolsEntries.isEmpty ? nil : JSONValue.array(googleToolsEntries)
        return GooglePreparedTools(tools: toolsValue, toolConfig: nil, toolWarnings: warnings)
    }

    var functionDeclarations: [JSONValue] = []

    for tool in tools {
        guard case .function(let functionTool) = tool else {
            warnings.append(.unsupportedTool(tool: tool, details: nil))
            continue
        }

        var declaration: [String: JSONValue] = [
            "name": .string(functionTool.name),
            "description": .string(functionTool.description ?? "")
        ]

        if let parameters = convertJSONSchemaToOpenAPISchema(functionTool.inputSchema),
           let parametersJSON = toJSONValue(parameters) {
            declaration["parameters"] = parametersJSON
        }

        functionDeclarations.append(.object(declaration))
    }

    let toolsPayload: JSONValue?
    if functionDeclarations.isEmpty {
        toolsPayload = nil
    } else {
        // Matches upstream Vercel AI SDK: `tools` is an array of tool objects.
        // For function tools, the payload is `[{ functionDeclarations: [...] }]`.
        toolsPayload = .array([
            .object([
                "functionDeclarations": .array(functionDeclarations)
            ])
        ])
    }

    let toolConfig: JSONValue?
    if let toolChoice {
        switch toolChoice {
        case .auto:
            toolConfig = .object([
                "functionCallingConfig": .object(["mode": .string("AUTO")])
            ])
        case .none:
            toolConfig = .object([
                "functionCallingConfig": .object(["mode": .string("NONE")])
            ])
        case .required:
            toolConfig = .object([
                "functionCallingConfig": .object(["mode": .string("ANY")])
            ])
        case .tool(let toolName):
            toolConfig = .object([
                "functionCallingConfig": .object([
                    "mode": .string("ANY"),
                    "allowedFunctionNames": .array([.string(toolName)])
                ])
            ])
        }
    } else {
        toolConfig = nil
    }

    return GooglePreparedTools(tools: toolsPayload, toolConfig: toolConfig, toolWarnings: warnings)
}
