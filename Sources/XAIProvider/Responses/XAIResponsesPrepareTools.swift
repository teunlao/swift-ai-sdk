import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Converts SDK tool definitions into the xAI Responses wire format.
/// Mirrors `packages/xai/src/responses/xai-responses-prepare-tools.ts`.
struct XAIResponsesPreparedTools {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

func prepareXAIResponsesTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) async throws -> XAIResponsesPreparedTools {
    let normalizedTools = tools?.isEmpty == true ? nil : tools
    var warnings: [SharedV3Warning] = []

    guard let normalizedTools else {
        return XAIResponsesPreparedTools(tools: nil, toolChoice: nil, warnings: warnings)
    }

    var xaiTools: [JSONValue] = []
    var toolByName: [String: LanguageModelV3Tool] = [:]

    for tool in normalizedTools {
        switch tool {
        case .provider(let providerTool):
            toolByName[providerTool.name] = tool

            switch providerTool.id {
            case "xai.web_search":
                let args = try await validateTypes(
                    ValidateTypesOptions(value: jsonValueToFoundation(.object(providerTool.args)), schema: xaiWebSearchArgsSchema)
                )

                var payload: [String: JSONValue] = [
                    "type": .string("web_search")
                ]
                if let allowed = args.allowedDomains {
                    payload["allowed_domains"] = .array(allowed.map(JSONValue.string))
                }
                if let excluded = args.excludedDomains {
                    payload["excluded_domains"] = .array(excluded.map(JSONValue.string))
                }
                if let enable = args.enableImageUnderstanding {
                    payload["enable_image_understanding"] = .bool(enable)
                }
                xaiTools.append(.object(payload))

            case "xai.x_search":
                let args = try await validateTypes(
                    ValidateTypesOptions(value: jsonValueToFoundation(.object(providerTool.args)), schema: xaiXSearchArgsSchema)
                )

                var payload: [String: JSONValue] = [
                    "type": .string("x_search")
                ]
                if let allowed = args.allowedXHandles {
                    payload["allowed_x_handles"] = .array(allowed.map(JSONValue.string))
                }
                if let excluded = args.excludedXHandles {
                    payload["excluded_x_handles"] = .array(excluded.map(JSONValue.string))
                }
                if let fromDate = args.fromDate {
                    payload["from_date"] = .string(fromDate)
                }
                if let toDate = args.toDate {
                    payload["to_date"] = .string(toDate)
                }
                if let enable = args.enableImageUnderstanding {
                    payload["enable_image_understanding"] = .bool(enable)
                }
                if let enable = args.enableVideoUnderstanding {
                    payload["enable_video_understanding"] = .bool(enable)
                }
                xaiTools.append(.object(payload))

            case "xai.code_execution":
                xaiTools.append(.object([
                    "type": .string("code_interpreter")
                ]))

            case "xai.view_image":
                xaiTools.append(.object([
                    "type": .string("view_image")
                ]))

            case "xai.view_x_video":
                xaiTools.append(.object([
                    "type": .string("view_x_video")
                ]))

            case "xai.file_search":
                let args = try await validateTypes(
                    ValidateTypesOptions(value: jsonValueToFoundation(.object(providerTool.args)), schema: xaiFileSearchArgsSchema)
                )

                var payload: [String: JSONValue] = [
                    "type": .string("file_search")
                ]
                payload["vector_store_ids"] = .array(args.vectorStoreIds.map(JSONValue.string))
                if let max = args.maxNumResults {
                    payload["max_num_results"] = .number(Double(max))
                }
                xaiTools.append(.object(payload))

            case "xai.mcp":
                let args = try await validateTypes(
                    ValidateTypesOptions(value: jsonValueToFoundation(.object(providerTool.args)), schema: xaiMcpServerArgsSchema)
                )

                var payload: [String: JSONValue] = [
                    "type": .string("mcp"),
                    "server_url": .string(args.serverUrl)
                ]
                if let label = args.serverLabel {
                    payload["server_label"] = .string(label)
                }
                if let description = args.serverDescription {
                    payload["server_description"] = .string(description)
                }
                if let allowedTools = args.allowedTools {
                    payload["allowed_tools"] = .array(allowedTools.map(JSONValue.string))
                }
                if let headers = args.headers {
                    payload["headers"] = .object(headers.mapValues(JSONValue.string))
                }
                if let authorization = args.authorization {
                    payload["authorization"] = .string(authorization)
                }
                xaiTools.append(.object(payload))

            default:
                warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.name)", details: nil))
            }

        case .function(let functionTool):
            toolByName[functionTool.name] = tool

            var payload: [String: JSONValue] = [
                "type": .string("function"),
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema
            ]

            if let description = functionTool.description {
                payload["description"] = .string(description)
            }

            xaiTools.append(.object(payload))
        }
    }

    let resolvedTools = xaiTools.isEmpty ? nil : xaiTools

    guard let toolChoice else {
        return XAIResponsesPreparedTools(tools: resolvedTools, toolChoice: nil, warnings: warnings)
    }

    let resolvedChoice: JSONValue?
    switch toolChoice {
    case .auto:
        resolvedChoice = .string("auto")
    case .none:
        resolvedChoice = .string("none")
    case .required:
        resolvedChoice = .string("required")
    case .tool(let toolName):
        guard let selectedTool = toolByName[toolName] else {
            return XAIResponsesPreparedTools(tools: resolvedTools, toolChoice: nil, warnings: warnings)
        }

        switch selectedTool {
        case .provider:
            warnings.append(.unsupported(
                feature: "toolChoice for server-side tool \"\(toolName)\"",
                details: nil
            ))
            resolvedChoice = nil
        case .function(let fn):
            resolvedChoice = .object([
                "type": .string("function"),
                "name": .string(fn.name)
            ])
        }
    }

    return XAIResponsesPreparedTools(tools: resolvedTools, toolChoice: resolvedChoice, warnings: warnings)
}
