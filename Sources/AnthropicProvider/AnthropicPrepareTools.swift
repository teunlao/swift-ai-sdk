import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicPreparedTools: Sendable {
    public let tools: [JSONValue]?
    public let toolChoice: JSONValue?
    public let warnings: [SharedV3Warning]
    public let betas: Set<String>
}

private func foundationArgs(_ args: [String: JSONValue]) -> [String: Any] {
    Dictionary(uniqueKeysWithValues: args.map { key, value in
        (key, jsonValueToFoundation(value))
    })
}

private func cacheControlJSON(from cacheControl: AnthropicCacheControl?) -> JSONValue? {
    guard let cacheControl else { return nil }
    var payload = cacheControl.additionalFields
    if let type = cacheControl.type {
        payload["type"] = .string(type)
    }
    if let ttl = cacheControl.ttl {
        payload["ttl"] = .string(ttl.rawValue)
    }
    return payload.isEmpty ? nil : .object(payload)
}

private func numberValue(_ value: JSONValue?) -> Double? {
    guard let value else { return nil }
    if case .number(let number) = value {
        return number
    }
    return nil
}

private func stringValue(_ value: JSONValue?) -> String? {
    guard let value else { return nil }
    if case .string(let string) = value {
        return string
    }
    return nil
}

private func boolValue(_ value: JSONValue?) -> Bool? {
    guard let value else { return nil }
    if case .bool(let bool) = value {
        return bool
    }
    return nil
}

public func prepareAnthropicTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    disableParallelToolUse: Bool?
) async throws -> AnthropicPreparedTools {
    guard let tools, !tools.isEmpty else {
        return AnthropicPreparedTools(tools: nil, toolChoice: nil, warnings: [], betas: [])
    }

    var anthropicTools: [JSONValue] = []
    var toolWarnings: [SharedV3Warning] = []
    var betas: Set<String> = []

    for tool in tools {
        switch tool {
        case .function(let functionTool):
            var payload: [String: JSONValue] = [
                "name": .string(functionTool.name),
                "input_schema": functionTool.inputSchema
            ]
            if let description = functionTool.description {
                payload["description"] = .string(description)
            }
            if let cacheControl = getAnthropicCacheControl(from: functionTool.providerOptions),
               let cacheJSON = cacheControlJSON(from: cacheControl) {
                payload["cache_control"] = cacheJSON
            }
            if let anthropicOptions = functionTool.providerOptions?["anthropic"] {
                if let deferLoadingValue = anthropicOptions["deferLoading"],
                   case .bool(let deferLoading) = deferLoadingValue {
                    payload["defer_loading"] = .bool(deferLoading)
                }

                if let allowedCallersValue = anthropicOptions["allowedCallers"],
                   case .array(let allowedCallersArray) = allowedCallersValue {
                    let callers: [JSONValue] = allowedCallersArray.compactMap { value in
                        guard case .string(let string) = value else { return nil }
                        return .string(string)
                    }
                    if callers.count == allowedCallersArray.count {
                        payload["allowed_callers"] = .array(callers)
                        betas.insert("advanced-tool-use-2025-11-20")
                    }
                }
            }
            anthropicTools.append(.object(payload))

        case .providerDefined(let providerTool):
            switch providerTool.id {
            case "anthropic.code_execution_20250522":
                betas.insert("code-execution-2025-05-22")
                anthropicTools.append(.object([
                    "type": .string("code_execution_20250522"),
                    "name": .string("code_execution")
                ]))

            case "anthropic.code_execution_20250825":
                betas.insert("code-execution-2025-08-25")
                anthropicTools.append(.object([
                    "type": .string("code_execution_20250825"),
                    "name": .string("code_execution")
                ]))

            case "anthropic.computer_20250124":
                betas.insert("computer-use-2025-01-24")
                let width = numberValue(providerTool.args["display_width_px"]) ?? 0
                let height = numberValue(providerTool.args["display_height_px"]) ?? 0
                var payload: [String: JSONValue] = [
                    "name": .string("computer"),
                    "type": .string("computer_20250124"),
                    "display_width_px": .number(width),
                    "display_height_px": .number(height)
                ]
                if let displayNumber = numberValue(providerTool.args["display_number"]) {
                    payload["display_number"] = .number(displayNumber)
                }
                anthropicTools.append(.object(payload))

            case "anthropic.computer_20251124":
                betas.insert("computer-use-2025-11-24")
                let width = numberValue(providerTool.args["display_width_px"]) ?? 0
                let height = numberValue(providerTool.args["display_height_px"]) ?? 0
                var payload: [String: JSONValue] = [
                    "name": .string("computer"),
                    "type": .string("computer_20251124"),
                    "display_width_px": .number(width),
                    "display_height_px": .number(height)
                ]
                if let displayNumber = numberValue(providerTool.args["display_number"]) {
                    payload["display_number"] = .number(displayNumber)
                }
                if let enableZoom = boolValue(providerTool.args["enable_zoom"]) {
                    payload["enable_zoom"] = .bool(enableZoom)
                }
                anthropicTools.append(.object(payload))

            case "anthropic.computer_20241022":
                betas.insert("computer-use-2024-10-22")
                let width = numberValue(providerTool.args["display_width_px"]) ?? 0
                let height = numberValue(providerTool.args["display_height_px"]) ?? 0
                var payload: [String: JSONValue] = [
                    "name": .string("computer"),
                    "type": .string("computer_20241022"),
                    "display_width_px": .number(width),
                    "display_height_px": .number(height)
                ]
                if let displayNumber = numberValue(providerTool.args["display_number"]) {
                    payload["display_number"] = .number(displayNumber)
                }
                anthropicTools.append(.object(payload))

            case "anthropic.text_editor_20250124":
                betas.insert("computer-use-2025-01-24")
                anthropicTools.append(.object([
                    "name": .string("str_replace_editor"),
                    "type": .string("text_editor_20250124")
                ]))

            case "anthropic.text_editor_20241022":
                betas.insert("computer-use-2024-10-22")
                anthropicTools.append(.object([
                    "name": .string("str_replace_editor"),
                    "type": .string("text_editor_20241022")
                ]))

            case "anthropic.text_editor_20250429":
                betas.insert("computer-use-2025-01-24")
                anthropicTools.append(.object([
                    "name": .string("str_replace_based_edit_tool"),
                    "type": .string("text_editor_20250429")
                ]))

            case "anthropic.text_editor_20250728":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: foundationArgs(providerTool.args), schema: anthropicTextEditor20250728ArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "name": .string("str_replace_based_edit_tool"),
                    "type": .string("text_editor_20250728")
                ]
                if let maxCharacters = parsed.maxCharacters {
                    payload["max_characters"] = .number(Double(maxCharacters))
                }
                anthropicTools.append(.object(payload))

            case "anthropic.bash_20250124":
                betas.insert("computer-use-2025-01-24")
                anthropicTools.append(.object([
                    "name": .string("bash"),
                    "type": .string("bash_20250124")
                ]))

            case "anthropic.bash_20241022":
                betas.insert("computer-use-2024-10-22")
                anthropicTools.append(.object([
                    "name": .string("bash"),
                    "type": .string("bash_20241022")
                ]))

            case "anthropic.memory_20250818":
                betas.insert("context-management-2025-06-27")
                anthropicTools.append(.object([
                    "name": .string("memory"),
                    "type": .string("memory_20250818")
                ]))

            case "anthropic.web_fetch_20250910":
                betas.insert("web-fetch-2025-09-10")
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: foundationArgs(providerTool.args), schema: anthropicWebFetch20250910ArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_fetch_20250910"),
                    "name": .string("web_fetch")
                ]
                if let maxUses = parsed.maxUses {
                    payload["max_uses"] = .number(Double(maxUses))
                }
                if let allowed = parsed.allowedDomains {
                    payload["allowed_domains"] = .array(allowed.map(JSONValue.string))
                }
                if let blocked = parsed.blockedDomains {
                    payload["blocked_domains"] = .array(blocked.map(JSONValue.string))
                }
                if let citations = parsed.citations, let enabled = citations.enabled {
                    payload["citations"] = .object(["enabled": .bool(enabled)])
                }
                if let maxContentTokens = parsed.maxContentTokens {
                    payload["max_content_tokens"] = .number(Double(maxContentTokens))
                }
                anthropicTools.append(.object(payload))

            case "anthropic.web_search_20250305":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: foundationArgs(providerTool.args), schema: anthropicWebSearch20250305ArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_search_20250305"),
                    "name": .string("web_search")
                ]
                if let maxUses = parsed.maxUses {
                    payload["max_uses"] = .number(Double(maxUses))
                }
                if let allowed = parsed.allowedDomains {
                    payload["allowed_domains"] = .array(allowed.map(JSONValue.string))
                }
                if let blocked = parsed.blockedDomains {
                    payload["blocked_domains"] = .array(blocked.map(JSONValue.string))
                }
                if let location = parsed.userLocation {
                    var locationPayload: [String: JSONValue] = [:]
                    if let type = location.type {
                        locationPayload["type"] = .string(type)
                    }
                    if let city = location.city {
                        locationPayload["city"] = .string(city)
                    }
                    if let region = location.region {
                        locationPayload["region"] = .string(region)
                    }
                    if let country = location.country {
                        locationPayload["country"] = .string(country)
                    }
                    if let timezone = location.timezone {
                        locationPayload["timezone"] = .string(timezone)
                    }
                    if !locationPayload.isEmpty {
                        payload["user_location"] = .object(locationPayload)
                    }
                }
                anthropicTools.append(.object(payload))

            case "anthropic.tool_search_regex_20251119":
                betas.insert("advanced-tool-use-2025-11-20")
                anthropicTools.append(.object([
                    "type": .string("tool_search_tool_regex_20251119"),
                    "name": .string("tool_search_tool_regex")
                ]))

            case "anthropic.tool_search_bm25_20251119":
                betas.insert("advanced-tool-use-2025-11-20")
                anthropicTools.append(.object([
                    "type": .string("tool_search_tool_bm25_20251119"),
                    "name": .string("tool_search_tool_bm25")
                ]))

            default:
                toolWarnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
            }
        }
    }

    // Normalize empty array to nil to mirror upstream behavior
    let normalizedTools = anthropicTools.isEmpty ? nil : anthropicTools

    guard let toolChoice else {
        let choiceJSON: JSONValue? = disableParallelToolUse == true ? .object([
            "type": .string("auto"),
            "disable_parallel_tool_use": .bool(true)
        ]) : nil
        return AnthropicPreparedTools(
            tools: normalizedTools,
            toolChoice: choiceJSON,
            warnings: toolWarnings,
            betas: betas
        )
    }

    func makeChoicePayload(type: String, extra: [String: JSONValue] = [:]) -> JSONValue {
        var payload: [String: JSONValue] = ["type": .string(type)]
        if let disableParallelToolUse {
            payload["disable_parallel_tool_use"] = .bool(disableParallelToolUse)
        }
        for (key, value) in extra {
            payload[key] = value
        }
        return .object(payload)
    }

    switch toolChoice {
    case .auto:
        return AnthropicPreparedTools(
            tools: normalizedTools,
            toolChoice: makeChoicePayload(type: "auto"),
            warnings: toolWarnings,
            betas: betas
        )

    case .required:
        return AnthropicPreparedTools(
            tools: normalizedTools,
            toolChoice: makeChoicePayload(type: "any"),
            warnings: toolWarnings,
            betas: betas
        )

    case .none:
        return AnthropicPreparedTools(
            tools: nil,
            toolChoice: nil,
            warnings: toolWarnings,
            betas: betas
        )

    case .tool(let toolName):
        return AnthropicPreparedTools(
            tools: normalizedTools,
            toolChoice: makeChoicePayload(type: "tool", extra: ["name": .string(toolName)]),
            warnings: toolWarnings,
            betas: betas
        )
    }
}
