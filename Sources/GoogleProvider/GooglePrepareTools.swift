import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GooglePreparedTools: Sendable {
    let tools: JSONValue?
    let toolConfig: JSONValue?
    let toolWarnings: [SharedV3Warning]
}

private func toJSONValue(_ value: Any) -> JSONValue? {
    try? jsonValue(from: value)
}

func prepareGoogleTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    modelId: GoogleGenerativeAIModelId
) -> GooglePreparedTools {
    var warnings: [SharedV3Warning] = []

    guard let tools, !tools.isEmpty else {
        return GooglePreparedTools(tools: nil, toolConfig: nil, toolWarnings: warnings)
    }

    let latestIds: Set<String> = [
        "gemini-flash-latest",
        "gemini-flash-lite-latest",
        "gemini-pro-latest"
    ]
    let modelIdString = modelId.rawValue

    let isGemini2OrNewer = modelIdString.contains("gemini-2") || modelIdString.contains("gemini-3") || latestIds.contains(modelIdString)
    let supportsDynamicRetrieval = modelIdString.contains("gemini-1.5-flash") && !modelIdString.contains("-8b")

    let hasFunctionTools = tools.contains { if case .function = $0 { return true } else { return false } }
    let hasProviderTools = tools.contains { if case .provider = $0 { return true } else { return false } }

    if hasFunctionTools && hasProviderTools {
        warnings.append(.unsupported(feature: "combination of function and provider-defined tools", details: nil))
    }

    if hasProviderTools {
        var googleToolsEntries: [JSONValue] = []

        for tool in tools {
            guard case .provider(let providerTool) = tool else { continue }

            switch providerTool.id {
            case "google.google_search":
                if isGemini2OrNewer {
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

            case "google.enterprise_web_search":
                if isGemini2OrNewer {
                    googleToolsEntries.append(.object([
                        "enterpriseWebSearch": .object([:])
                    ]))
                } else {
                    warnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "Enterprise Web Search requires Gemini 2.0 or newer."
                        )
                    )
                }

            case "google.url_context":
                if isGemini2OrNewer {
                    googleToolsEntries.append(.object([
                        "urlContext": .object([:])
                    ]))
                } else {
                    warnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "The URL context tool is not supported with other Gemini models than Gemini 2."
                        )
                    )
                }

            case "google.code_execution":
                if isGemini2OrNewer {
                    googleToolsEntries.append(.object([
                        "codeExecution": .object([:])
                    ]))
                } else {
                    warnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "The code execution tools is not supported with other Gemini models than Gemini 2."
                        )
                    )
                }

            case "google.file_search":
                let supportsFileSearch = modelIdString.contains("gemini-2.5") || modelIdString.contains("gemini-3")
                if supportsFileSearch {
                    googleToolsEntries.append(.object([
                        "fileSearch": .object(providerTool.args)
                    ]))
                } else {
                    warnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "The file search tool is only supported with Gemini 2.5 models and Gemini 3 models."
                        )
                    )
                }

            case "google.vertex_rag_store":
                if isGemini2OrNewer {
                    let ragCorpus = providerTool.args["ragCorpus"] ?? .null
                    let topK = providerTool.args["topK"] ?? .null
                    googleToolsEntries.append(.object([
                        "retrieval": .object([
                            "vertex_rag_store": .object([
                                "rag_resources": .object([
                                    "rag_corpus": ragCorpus
                                ]),
                                "similarity_top_k": topK
                            ])
                        ])
                    ]))
                } else {
                    warnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "The RAG store tool is not supported with other Gemini models than Gemini 2."
                        )
                    )
                }

            case "google.google_maps":
                if isGemini2OrNewer {
                    googleToolsEntries.append(.object([
                        "googleMaps": .object([:])
                    ]))
                } else {
                    warnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "The Google Maps grounding tool is not supported with Gemini models other than Gemini 2 or newer."
                        )
                    )
                }

            default:
                warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
            }
        }

        let toolsValue = googleToolsEntries.isEmpty ? nil : JSONValue.array(googleToolsEntries)
        return GooglePreparedTools(tools: toolsValue, toolConfig: nil, toolWarnings: warnings)
    }

    var functionDeclarations: [JSONValue] = []

    for tool in tools {
        guard case .function(let functionTool) = tool else {
            if case .provider(let providerTool) = tool {
                warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
            }
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
