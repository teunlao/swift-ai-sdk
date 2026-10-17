import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicPreparedTools: Sendable {
    public let tools: [JSONValue]?
    public let toolChoice: JSONValue?
    public let warnings: [SharedV4Warning]
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

private func integerValue(_ value: JSONValue?) throws -> Int? {
    guard let value else { return nil }
    guard case .number(let number) = value, let integer = Int(exactly: number) else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "Computer display values must be representable integers"))
    }
    return integer
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
    tools: [LanguageModelV4Tool]?,
    toolChoice: LanguageModelV4ToolChoice?,
    disableParallelToolUse: Bool?,
    supportsStructuredOutput: Bool = false,
    supportsStrictTools: Bool = false,
    rejectsForcedToolUse: Bool = false,
    cacheControlValidator: CacheControlValidator? = nil,
    defaultEagerInputStreaming: Bool = false
) async throws -> AnthropicPreparedTools {
    guard let tools, !tools.isEmpty else {
        return AnthropicPreparedTools(tools: nil, toolChoice: nil, warnings: [], betas: [])
    }

    var anthropicTools: [JSONValue] = []
    var toolWarnings: [SharedV4Warning] = []
    var betas: Set<String> = []
    let validator = cacheControlValidator ?? CacheControlValidator()

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

            if supportsStrictTools, let strict = functionTool.strict {
                payload["strict"] = .bool(strict)
            } else if !supportsStrictTools, functionTool.strict == true {
                toolWarnings.append(.unsupported(
                    feature: "strict",
                    details: "Tool '\(functionTool.name)' has strict: true, but strict mode is not supported by this provider. The strict property will be ignored."
                ))
            }
            if supportsStructuredOutput {
                betas.insert("structured-outputs-2025-11-13")
            }

            let cacheControl = validator.getCacheControl(
                functionTool.providerOptions,
                context: CacheControlContext(type: "tool definition", canCache: true)
            )
            if let cacheJSON = cacheControlJSON(from: cacheControl) {
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

            // eager_input_streaming is only supported on custom (function) tools.
            // Fall back to the model-level default when the tool doesn't set it.
            let eagerInputStreaming: Bool? = {
                if let anthropicOptions = functionTool.providerOptions?["anthropic"],
                   let value = anthropicOptions["eagerInputStreaming"],
                   case .bool(let flag) = value {
                    return flag
                }
                return defaultEagerInputStreaming ? true : nil
            }()
            if eagerInputStreaming == true {
                payload["eager_input_streaming"] = .bool(true)
            }

            if let inputExamples = functionTool.inputExamples {
                payload["input_examples"] = .array(inputExamples.map { .object($0.input) })
                betas.insert("advanced-tool-use-2025-11-20")
            }
            anthropicTools.append(.object(payload))

        case .provider(let providerTool):
            switch providerTool.id {
            case "anthropic.advisor_20260301":
                betas.insert("advisor-tool-2026-03-01")
                let parsed = try await validateTypes(
                    ValidateTypesOptions(
                        value: foundationArgs(providerTool.args),
                        schema: anthropicAdvisor20260301ArgsSchema
                    )
                )
                var payload: [String: JSONValue] = [
                    "type": .string("advisor_20260301"),
                    "name": .string("advisor"),
                    "model": .string(parsed.model),
                ]
                if let maxUses = parsed.maxUses {
                    payload["max_uses"] = .number(Double(maxUses))
                }
                if let maxTokens = parsed.maxTokens {
                    payload["max_tokens"] = .number(Double(maxTokens))
                }
                if let caching = parsed.caching {
                    payload["caching"] = .object([
                        "type": .string(caching.type.rawValue),
                        "ttl": .string(caching.ttl.rawValue),
                    ])
                }
                anthropicTools.append(.object(payload))

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

            case "anthropic.code_execution_20260120":
                anthropicTools.append(.object([
                    "type": .string("code_execution_20260120"),
                    "name": .string("code_execution")
                ]))

            case "anthropic.computer_toolset_20260801":
                let parsed = try await validateTypes(ValidateTypesOptions(
                    value: foundationArgs(providerTool.args),
                    schema: anthropicComputerToolset20260801ArgsSchema
                ))
                var payload: [String: JSONValue] = ["type": .string("computer_toolset_20260801")]
                if let configs = parsed.configs {
                    payload["configs"] = .object(configs.mapValues { config in
                        var value: [String: JSONValue] = [:]
                        if let enabled = config.enabled { value["enabled"] = .bool(enabled) }
                        if let deferLoading = config.deferLoading { value["defer_loading"] = .bool(deferLoading) }
                        return .object(value)
                    })
                }
                anthropicTools.append(.object(payload))

            case "anthropic.computer_20250124":
                betas.insert("computer-use-2025-01-24")
                let width = try integerValue(providerTool.args["displayWidthPx"])
                let height = try integerValue(providerTool.args["displayHeightPx"])
                var payload: [String: JSONValue] = [
                    "name": .string("computer"),
                    "type": .string("computer_20250124")
                ]
                if let width { payload["display_width_px"] = .number(Double(width)) }
                if let height { payload["display_height_px"] = .number(Double(height)) }
                if let displayNumber = try integerValue(providerTool.args["displayNumber"]) {
                    payload["display_number"] = .number(Double(displayNumber))
                }
                anthropicTools.append(.object(payload))

            case "anthropic.computer_20251124":
                betas.insert("computer-use-2025-11-24")
                let width = try integerValue(providerTool.args["displayWidthPx"])
                let height = try integerValue(providerTool.args["displayHeightPx"])
                var payload: [String: JSONValue] = [
                    "name": .string("computer"),
                    "type": .string("computer_20251124")
                ]
                if let width { payload["display_width_px"] = .number(Double(width)) }
                if let height { payload["display_height_px"] = .number(Double(height)) }
                if let displayNumber = try integerValue(providerTool.args["displayNumber"]) {
                    payload["display_number"] = .number(Double(displayNumber))
                }
                if let enableZoom = boolValue(providerTool.args["enableZoom"]) {
                    payload["enable_zoom"] = .bool(enableZoom)
                }
                anthropicTools.append(.object(payload))

            case "anthropic.computer_20241022":
                betas.insert("computer-use-2024-10-22")
                let width = try integerValue(providerTool.args["displayWidthPx"])
                let height = try integerValue(providerTool.args["displayHeightPx"])
                var payload: [String: JSONValue] = [
                    "name": .string("computer"),
                    "type": .string("computer_20241022")
                ]
                if let width { payload["display_width_px"] = .number(Double(width)) }
                if let height { payload["display_height_px"] = .number(Double(height)) }
                if let displayNumber = try integerValue(providerTool.args["displayNumber"]) {
                    payload["display_number"] = .number(Double(displayNumber))
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
                if let citations = parsed.citations {
                    payload["citations"] = .object(["enabled": .bool(citations.enabled)])
                }
                if let maxContentTokens = parsed.maxContentTokens {
                    payload["max_content_tokens"] = .number(Double(maxContentTokens))
                }
                anthropicTools.append(.object(payload))

            case "anthropic.web_fetch_20260209":
                betas.insert("code-execution-web-tools-2026-02-09")
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: foundationArgs(providerTool.args), schema: anthropicWebFetch20260209ArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_fetch_20260209"),
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
                if let citations = parsed.citations {
                    payload["citations"] = .object(["enabled": .bool(citations.enabled)])
                }
                if let maxContentTokens = parsed.maxContentTokens {
                    payload["max_content_tokens"] = .number(Double(maxContentTokens))
                }
                anthropicTools.append(.object(payload))

            case "anthropic.web_fetch_20260318":
                let parsed = try await validateTypes(ValidateTypesOptions(
                    value: foundationArgs(providerTool.args),
                    schema: anthropicWebFetch20260318ArgsSchema
                ))
                var payload: [String: JSONValue] = [
                    "type": .string("web_fetch_20260318"),
                    "name": .string("web_fetch"),
                ]
                if let maxUses = parsed.maxUses { payload["max_uses"] = .number(Double(maxUses)) }
                if let domains = parsed.allowedDomains { payload["allowed_domains"] = .array(domains.map(JSONValue.string)) }
                if let domains = parsed.blockedDomains { payload["blocked_domains"] = .array(domains.map(JSONValue.string)) }
                if let citations = parsed.citations { payload["citations"] = .object(["enabled": .bool(citations.enabled)]) }
                if let tokens = parsed.maxContentTokens { payload["max_content_tokens"] = .number(Double(tokens)) }
                if let useCache = parsed.useCache { payload["use_cache"] = .bool(useCache) }
                if let inclusion = parsed.responseInclusion { payload["response_inclusion"] = .string(inclusion.rawValue) }
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
                    locationPayload["type"] = .string(location.type.rawValue)
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

            case "anthropic.web_search_20260209":
                betas.insert("code-execution-web-tools-2026-02-09")
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: foundationArgs(providerTool.args), schema: anthropicWebSearch20260209ArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_search_20260209"),
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
                    locationPayload["type"] = .string(location.type.rawValue)
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

            case "anthropic.web_search_20260318":
                let parsed = try await validateTypes(ValidateTypesOptions(
                    value: foundationArgs(providerTool.args),
                    schema: anthropicWebSearch20260318ArgsSchema
                ))
                var payload: [String: JSONValue] = [
                    "type": .string("web_search_20260318"),
                    "name": .string("web_search"),
                ]
                if let maxUses = parsed.maxUses { payload["max_uses"] = .number(Double(maxUses)) }
                if let domains = parsed.allowedDomains { payload["allowed_domains"] = .array(domains.map(JSONValue.string)) }
                if let domains = parsed.blockedDomains { payload["blocked_domains"] = .array(domains.map(JSONValue.string)) }
                if let location = parsed.userLocation {
                    var value: [String: JSONValue] = ["type": .string(location.type.rawValue)]
                    if let city = location.city { value["city"] = .string(city) }
                    if let region = location.region { value["region"] = .string(region) }
                    if let country = location.country { value["country"] = .string(country) }
                    if let timezone = location.timezone { value["timezone"] = .string(timezone) }
                    payload["user_location"] = .object(value)
                }
                if let inclusion = parsed.responseInclusion { payload["response_inclusion"] = .string(inclusion.rawValue) }
                anthropicTools.append(.object(payload))

            case "anthropic.tool_search_regex_20251119":
                anthropicTools.append(.object([
                    "type": .string("tool_search_tool_regex_20251119"),
                    "name": .string("tool_search_tool_regex")
                ]))

            case "anthropic.tool_search_bm25_20251119":
                anthropicTools.append(.object([
                    "type": .string("tool_search_tool_bm25_20251119"),
                    "name": .string("tool_search_tool_bm25")
                ]))

            default:
                toolWarnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
            }
        }
    }

    let preparedTools = anthropicTools

    guard let toolChoice else {
        let choiceJSON: JSONValue? = disableParallelToolUse == true ? .object([
            "type": .string("auto"),
            "disable_parallel_tool_use": .bool(true)
        ]) : nil
        return AnthropicPreparedTools(
            tools: preparedTools,
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
            tools: preparedTools,
            toolChoice: makeChoicePayload(type: "auto"),
            warnings: toolWarnings,
            betas: betas
        )

    case .required:
        if rejectsForcedToolUse {
            toolWarnings.append(.unsupported(
                feature: "toolChoice",
                details: "toolChoice 'required' is not supported with this model or thinking configuration. Using 'auto' instead. Instruct the model to use a tool in the prompt and verify that a tool call was made."
            ))
            return AnthropicPreparedTools(
                tools: preparedTools,
                toolChoice: makeChoicePayload(type: "auto"),
                warnings: toolWarnings,
                betas: betas
            )
        }
        return AnthropicPreparedTools(
            tools: preparedTools,
            toolChoice: makeChoicePayload(type: "any"),
            warnings: toolWarnings,
            betas: betas
        )

    case .none:
        return AnthropicPreparedTools(
            tools: preparedTools,
            toolChoice: .object(["type": .string("none")]),
            warnings: toolWarnings,
            betas: betas
        )

    case .tool(let toolName):
        if rejectsForcedToolUse {
            toolWarnings.append(.unsupported(
                feature: "toolChoice",
                details: "toolChoice 'tool' is not supported with this model or thinking configuration. Only the '\(toolName)' tool is sent with 'auto' tool choice. Instruct the model to use the tool in the prompt and verify that a tool call was made."
            ))
            return AnthropicPreparedTools(
                tools: preparedTools.filter { tool in
                    guard case .object(let value) = tool else { return false }
                    return value["name"] == .string(toolName)
                },
                toolChoice: makeChoicePayload(type: "auto"),
                warnings: toolWarnings,
                betas: betas
            )
        }
        return AnthropicPreparedTools(
            tools: preparedTools,
            toolChoice: makeChoicePayload(type: "tool", extra: ["name": .string(toolName)]),
            warnings: toolWarnings,
            betas: betas
        )
    }
}
