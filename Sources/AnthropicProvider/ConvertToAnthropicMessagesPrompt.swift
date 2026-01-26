import Foundation
import AISDKProvider
import AISDKProviderUtils

struct AnthropicPromptConversionResult: Sendable {
    let prompt: AnthropicMessagesPrompt
    let betas: Set<String>
}

func convertToAnthropicMessagesPrompt(
    prompt: LanguageModelV3Prompt,
    sendReasoning: Bool,
    toolNameMapping: AnthropicToolNameMapping = .init(),
    warnings: inout [LanguageModelV3CallWarning]
) async throws -> AnthropicPromptConversionResult {
    let blocks = groupIntoAnthropicBlocks(prompt)

    var systemContent: [JSONValue]? = nil
    var messages: [AnthropicMessage] = []
    var betas = Set<String>()
    var mcpToolUseIds = Set<String>()

    for (blockIndex, block) in blocks.enumerated() {
        let isLastBlock = blockIndex == blocks.count - 1

        switch block {
        case .system(let systemMessages):
            if systemContent != nil {
                throw UnsupportedFunctionalityError(
                    functionality: "Multiple system messages that are separated by user/assistant messages"
                )
            }

            var aggregated = systemContent ?? []

            for case let .system(text, providerOptions) in systemMessages {
                var payload: [String: JSONValue] = [
                    "type": .string("text"),
                    "text": .string(text)
                ]
                if let cacheControl = cacheControlJSON(from: getAnthropicCacheControl(from: providerOptions)) {
                    payload["cache_control"] = cacheControl
                }
                aggregated.append(.object(payload))
            }

            systemContent = aggregated.isEmpty ? nil : aggregated

        case .user(let userMessages):
            var content: [JSONValue] = []

            for message in userMessages {
                switch message {
                case let .user(parts, providerOptions):
                    try await appendUserMessageParts(
                        parts,
                        messageProviderOptions: providerOptions,
                        anthropicContent: &content,
                        betas: &betas
                    )
                case let .tool(parts, providerOptions):
                    try await appendToolMessageParts(
                        parts,
                        messageProviderOptions: providerOptions,
                        anthropicContent: &content,
                        betas: &betas,
                        warnings: &warnings
                    )
                default:
                    break
                }
            }

            messages.append(AnthropicMessage(role: "user", content: content))

        case .assistant(let assistantMessages):
            var content: [JSONValue] = []

            for (messageIndex, message) in assistantMessages.enumerated() {
                guard case let .assistant(parts, providerOptions) = message else { continue }
                let isLastMessage = messageIndex == assistantMessages.count - 1

                try await appendAssistantMessageParts(
                    parts,
                    messageProviderOptions: providerOptions,
                    isLastBlock: isLastBlock,
                    isLastMessage: isLastMessage,
                    anthropicContent: &content,
                    betas: &betas,
                    mcpToolUseIds: &mcpToolUseIds,
                    sendReasoning: sendReasoning,
                    toolNameMapping: toolNameMapping,
                    warnings: &warnings
                )
            }

            messages.append(AnthropicMessage(role: "assistant", content: content))
        }
    }

    let payload = AnthropicMessagesPrompt(system: systemContent, messages: messages)
    return AnthropicPromptConversionResult(prompt: payload, betas: betas)
}

private enum AnthropicPromptBlock: Sendable {
    case system([LanguageModelV3Message])
    case assistant([LanguageModelV3Message])
    case user([LanguageModelV3Message])
}

private func groupIntoAnthropicBlocks(_ prompt: LanguageModelV3Prompt) -> [AnthropicPromptBlock] {
    var blocks: [AnthropicPromptBlock] = []

    for message in prompt {
        switch message.roleVariant {
        case .system:
            if let last = blocks.indices.last, case var .system(messages) = blocks[last] {
                messages.append(message)
                blocks[last] = .system(messages)
            } else {
                blocks.append(.system([message]))
            }

        case .assistant:
            if let last = blocks.indices.last, case var .assistant(messages) = blocks[last] {
                messages.append(message)
                blocks[last] = .assistant(messages)
            } else {
                blocks.append(.assistant([message]))
            }

        case .user, .tool:
            if let last = blocks.indices.last, case var .user(messages) = blocks[last] {
                messages.append(message)
                blocks[last] = .user(messages)
            } else {
                blocks.append(.user([message]))
            }
        }
    }

    return blocks
}

private func appendUserMessageParts(
    _ parts: [LanguageModelV3UserMessagePart],
    messageProviderOptions: SharedV3ProviderOptions?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>
) async throws {
    for (index, part) in parts.enumerated() {
        let isLastPart = index == parts.count - 1

        switch part {
        case .text(let textPart):
            let cacheControl = getAnthropicCacheControl(from: textPart.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
            let cacheControlJSON = cacheControlJSON(from: cacheControl)

            var payload: [String: JSONValue] = [
                "type": .string("text"),
                "text": .string(textPart.text)
            ]
            if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
            anthropicContent.append(.object(payload))

        case .file(let filePart):
            let cacheControl = getAnthropicCacheControl(from: filePart.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
            let cacheControlJSON = cacheControlJSON(from: cacheControl)
            try await appendUserFile(
                filePart,
                messageProviderOptions: messageProviderOptions,
                cacheControlJSON: cacheControlJSON,
                anthropicContent: &anthropicContent,
                betas: &betas
            )
        }
    }
}

private func appendUserFile(
    _ filePart: LanguageModelV3FilePart,
    messageProviderOptions: SharedV3ProviderOptions?,
    cacheControlJSON: JSONValue?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>
) async throws {
    let providerOptions = try await parseProviderOptions(
        provider: "anthropic",
        providerOptions: filePart.providerOptions,
        schema: anthropicFilePartProviderOptionsSchema
    )

    let title = providerOptions?.title ?? filePart.filename
    let citationsEnabled = providerOptions?.citations?.enabled ?? false
    let context = providerOptions?.context

    switch filePart.mediaType {
    case let media where media.hasPrefix("image/"):
        var source: [String: JSONValue]
        switch filePart.data {
        case .url(let url):
            source = [
                "type": .string("url"),
                "url": .string(url.absoluteString)
            ]
        case .data(let data):
            source = [
                "type": .string("base64"),
                "media_type": .string(media == "image/*" ? "image/jpeg" : media),
                "data": .string(convertDataToBase64(data))
            ]
        case .base64(let base64):
            source = [
                "type": .string("base64"),
                "media_type": .string(media == "image/*" ? "image/jpeg" : media),
                "data": .string(base64)
            ]
        }

        var payload: [String: JSONValue] = [
            "type": .string("image"),
            "source": .object(source)
        ]
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    case "application/pdf":
        betas.insert("pdfs-2024-09-25")

        let source: JSONValue
        switch filePart.data {
        case .url(let url):
            source = .object([
                "type": .string("url"),
                "url": .string(url.absoluteString)
            ])
        case .data(let data):
            source = .object([
                "type": .string("base64"),
                "media_type": .string("application/pdf"),
                "data": .string(convertDataToBase64(data))
            ])
        case .base64(let string):
            source = .object([
                "type": .string("base64"),
                "media_type": .string("application/pdf"),
                "data": .string(string)
            ])
        }

        var payload: [String: JSONValue] = [
            "type": .string("document"),
            "source": source
        ]
        if let title { payload["title"] = .string(title) }
        if let context { payload["context"] = .string(context) }
        if citationsEnabled { payload["citations"] = .object(["enabled": .bool(true)]) }
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    case "text/plain":
        let source: JSONValue
        switch filePart.data {
        case .url(let url):
            source = .object([
                "type": .string("url"),
                "url": .string(url.absoluteString)
            ])
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "text/plain encoding", message: "Expected UTF-8 data")
            }
            source = .object([
                "type": .string("text"),
                "media_type": .string("text/plain"),
                "data": .string(text)
            ])
        case .base64(let base64):
            let data = try convertBase64ToData(base64)
            guard let text = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "text/plain encoding", message: "Expected UTF-8 data")
            }
            source = .object([
                "type": .string("text"),
                "media_type": .string("text/plain"),
                "data": .string(text)
            ])
        }

        var payload: [String: JSONValue] = [
            "type": .string("document"),
            "source": source
        ]
        if let title { payload["title"] = .string(title) }
        if let context { payload["context"] = .string(context) }
        if citationsEnabled { payload["citations"] = .object(["enabled": .bool(true)]) }
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    default:
        throw UnsupportedFunctionalityError(functionality: "media type", message: filePart.mediaType)
    }
}

private func appendToolMessageParts(
    _ parts: [LanguageModelV3ToolMessagePart],
    messageProviderOptions: SharedV3ProviderOptions?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    warnings: inout [LanguageModelV3CallWarning]
) async throws {
    let toolResultParts: [LanguageModelV3ToolResultPart] = parts.compactMap { part in
        if case .toolResult(let result) = part { return result }
        return nil
    }

    for (index, part) in toolResultParts.enumerated() {
        let isLastPart = index == toolResultParts.count - 1
        let cacheControl = getAnthropicCacheControl(from: part.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
        let cacheControlJSON = cacheControlJSON(from: cacheControl)

        var payload: [String: JSONValue] = [
            "type": .string("tool_result"),
            "tool_use_id": .string(part.toolCallId)
        ]

        switch part.output {
        case .content(let items, _):
            let mapped = items.map { item -> JSONValue in
                switch item {
                case .text(let text):
                    return .object([
                        "type": .string("text"),
                        "text": .string(text)
                    ])
                case .media(let data, let mediaType):
                    if mediaType == "application/pdf" {
                        betas.insert("pdfs-2024-09-25")
                    }
                    return .object([
                        "type": mediaType == "application/pdf" ? .string("document") : .string("image"),
                        "source": .object([
                            "type": .string("base64"),
                            "media_type": .string(mediaType),
                            "data": .string(data)
                        ])
                    ])
                }
            }
            payload["content"] = .array(mapped)

        case .text(let value, _):
            payload["content"] = .string(value)
        case .errorText(let value, _):
            payload["content"] = .string(value)
            payload["is_error"] = .bool(true)
        case .executionDenied(let reason, _):
            payload["content"] = .string(reason ?? "Tool execution denied.")
        case .json(let value, _), .errorJson(let value, _):
            payload["content"] = .string(try jsonString(from: value))
            if case .errorJson = part.output {
                payload["is_error"] = .bool(true)
            }
        }

        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))
    }
}

private func appendAssistantMessageParts(
    _ parts: [LanguageModelV3MessagePart],
    messageProviderOptions: SharedV3ProviderOptions?,
    isLastBlock: Bool,
    isLastMessage: Bool,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    mcpToolUseIds: inout Set<String>,
    sendReasoning: Bool,
    toolNameMapping: AnthropicToolNameMapping,
    warnings: inout [LanguageModelV3CallWarning]
) async throws {
    for (index, part) in parts.enumerated() {
        let isLastPart = index == parts.count - 1

        switch part {
        case .text(let textPart):
            let cacheControl = getAnthropicCacheControl(from: textPart.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
            let cacheControlJSON = cacheControlJSON(from: cacheControl)

            var text = textPart.text
            if isLastBlock && isLastMessage && isLastPart {
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var payload: [String: JSONValue] = [
                "type": .string("text"),
                "text": .string(text)
            ]
            if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
            anthropicContent.append(.object(payload))

        case .reasoning(let reasoningPart):
            let cacheControl = getAnthropicCacheControl(from: reasoningPart.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
            let cacheControlJSON = cacheControlJSON(from: cacheControl)

            if sendReasoning {
                let metadata = try await parseProviderOptions(
                    provider: "anthropic",
                    providerOptions: reasoningPart.providerOptions,
                    schema: anthropicReasoningMetadataSchema
                )

                if let metadata, let signature = metadata.signature {
                    var payload: [String: JSONValue] = [
                        "type": .string("thinking"),
                        "thinking": .string(reasoningPart.text),
                        "signature": .string(signature)
                    ]
                    if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
                    anthropicContent.append(.object(payload))
                } else if let metadata, let redacted = metadata.redactedData {
                    var payload: [String: JSONValue] = [
                        "type": .string("redacted_thinking"),
                        "data": .string(redacted)
                    ]
                    if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
                    anthropicContent.append(.object(payload))
                } else {
                    warnings.append(.other(message: "unsupported reasoning metadata"))
                }
            } else {
                warnings.append(.other(message: "sending reasoning content is disabled for this model"))
            }

        case .toolCall(let toolCallPart):
            let cacheControl = getAnthropicCacheControl(from: toolCallPart.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
            let cacheControlJSON = cacheControlJSON(from: cacheControl)

            var payload: [String: JSONValue]
            if toolCallPart.providerExecuted == true {
                if let anthropicProviderOptions = toolCallPart.providerOptions?["anthropic"],
                   let type = anthropicProviderOptions["type"],
                   type == .string("mcp-tool-use") {
                    mcpToolUseIds.insert(toolCallPart.toolCallId)

                    guard let serverNameValue = anthropicProviderOptions["serverName"],
                          case .string(let serverName) = serverNameValue
                    else {
                        warnings.append(.other(message: "mcp tool use server name is required and must be a string"))
                        continue
                    }

                    payload = [
                        "type": .string("mcp_tool_use"),
                        "id": .string(toolCallPart.toolCallId),
                        "name": .string(toolCallPart.toolName),
                        "input": toolCallPart.input,
                        "server_name": .string(serverName)
                    ]
                    if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
                    anthropicContent.append(.object(payload))
                    continue
                }

                let providerToolName = toolNameMapping.toProviderToolName(toolCallPart.toolName)

                if providerToolName == "code_execution",
                   case .object(let inputObject) = toolCallPart.input,
                   let typeValue = inputObject["type"],
                   case .string(let subtoolName) = typeValue,
                   subtoolName == "bash_code_execution" || subtoolName == "text_editor_code_execution" {
                    // code execution 20250825: map back to subtool name
                    payload = [
                        "type": .string("server_tool_use"),
                        "id": .string(toolCallPart.toolCallId),
                        "name": .string(subtoolName),
                        "input": toolCallPart.input
                    ]
                } else if providerToolName == "code_execution",
                          case .object(let inputObject) = toolCallPart.input,
                          let typeValue = inputObject["type"],
                          typeValue == .string("programmatic-tool-call") {
                    // code execution 20250825 programmatic tool calling:
                    // Strip the fake 'programmatic-tool-call' type before sending to Anthropic
                    var inputWithoutType = inputObject
                    inputWithoutType.removeValue(forKey: "type")
                    payload = [
                        "type": .string("server_tool_use"),
                        "id": .string(toolCallPart.toolCallId),
                        "name": .string("code_execution"),
                        "input": .object(inputWithoutType)
                    ]
                } else if providerToolName == "code_execution"
                            || providerToolName == "web_fetch"
                            || providerToolName == "web_search"
                            || providerToolName == "tool_search_tool_regex"
                            || providerToolName == "tool_search_tool_bm25" {
                    payload = [
                        "type": .string("server_tool_use"),
                        "id": .string(toolCallPart.toolCallId),
                        "name": .string(providerToolName),
                        "input": toolCallPart.input
                    ]
                } else {
                    warnings.append(.other(message: "provider executed tool call for tool \(toolCallPart.toolName) is not supported"))
                    continue
                }
            } else {
                payload = [
                    "type": .string("tool_use"),
                    "id": .string(toolCallPart.toolCallId),
                    "name": .string(toolCallPart.toolName),
                    "input": toolCallPart.input
                ]

                if let anthropicOptions = toolCallPart.providerOptions?["anthropic"],
                   let callerValue = anthropicOptions["caller"],
                   case .object(let callerObject) = callerValue,
                   let typeValue = callerObject["type"],
                   case .string(let callerType) = typeValue {
                    if callerType == "code_execution_20250825",
                       let toolIdValue = callerObject["toolId"],
                       case .string(let toolId) = toolIdValue {
                        payload["caller"] = .object([
                            "type": .string("code_execution_20250825"),
                            "tool_id": .string(toolId),
                        ])
                    } else if callerType == "direct" {
                        payload["caller"] = .object([
                            "type": .string("direct")
                        ])
                    }
                }
            }
            if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
            anthropicContent.append(.object(payload))

        case .toolResult(let toolResultPart):
            let cacheControl = getAnthropicCacheControl(from: toolResultPart.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
            let cacheControlJSON = cacheControlJSON(from: cacheControl)
            try await appendAssistantToolResult(
                toolResultPart,
                cacheControlJSON: cacheControlJSON,
                anthropicContent: &anthropicContent,
                betas: &betas,
                mcpToolUseIds: mcpToolUseIds,
                toolNameMapping: toolNameMapping,
                warnings: &warnings
            )

        case .file:
            throw UnsupportedFunctionalityError(functionality: "assistant file content")
        }
    }
}
private func appendAssistantToolResult(
    _ part: LanguageModelV3ToolResultPart,
    cacheControlJSON: JSONValue?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    mcpToolUseIds: Set<String>,
    toolNameMapping: AnthropicToolNameMapping,
    warnings: inout [LanguageModelV3CallWarning]
) async throws {
    if mcpToolUseIds.contains(part.toolCallId) {
        var payload: [String: JSONValue] = [
            "type": .string("mcp_tool_result"),
            "tool_use_id": .string(part.toolCallId)
        ]

        switch part.output {
        case .json(let value, _):
            payload["is_error"] = .bool(false)
            payload["content"] = value
        case .errorJson(let value, _):
            payload["is_error"] = .bool(true)
            payload["content"] = value
        default:
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

        // Match upstream behavior: mcp tool results are still treated as unsupported
        // provider-executed tool results for warnings purposes.
        warnings.append(.other(message: "provider executed tool result for tool \(part.toolName) is not supported"))
        return
    }

    switch part.toolName {
    case "code_execution":
        guard case .json(let value, _) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let parsed = try await validateTypes(
            ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicCodeExecution20250522OutputSchema)
        )

        var payload: [String: JSONValue] = [
            "type": .string("code_execution_tool_result"),
            "tool_use_id": .string(part.toolCallId),
            "content": .object([
                "type": .string(parsed.type),
                "stdout": .string(parsed.stdout),
                "stderr": .string(parsed.stderr),
                "return_code": .number(Double(parsed.returnCode))
            ])
        ]
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    case "web_fetch":
        guard case .json(let value, _) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let parsed = try await validateTypes(
            ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicWebFetch20250910OutputSchema)
        )

        var contentPayload: [String: JSONValue] = [
            "type": .string("document"),
            "title": .string(parsed.content.title),
            "source": .object([
                "type": .string(parsed.content.source.type),
                "media_type": .string(parsed.content.source.mediaType),
                "data": .string(parsed.content.source.data)
            ])
        ]
        if let citations = parsed.content.citations {
            contentPayload["citations"] = .object(["enabled": .bool(citations.enabled)])
        }

        var payload: [String: JSONValue] = [
            "type": .string("web_fetch_tool_result"),
            "tool_use_id": .string(part.toolCallId),
            "content": .object([
                "type": .string("web_fetch_result"),
                "url": .string(parsed.url),
                "retrieved_at": parsed.retrievedAt.map(JSONValue.string) ?? .null,
                "content": .object(contentPayload)
            ])
        ]
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    case "web_search":
        guard case .json(let value, _) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let results = try await validateTypes(
            ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicWebSearch20250305OutputSchema)
        )

        let mapped = results.map { result in
            JSONValue.object([
                "url": .string(result.url),
                "title": .string(result.title),
                "page_age": result.pageAge.map(JSONValue.string) ?? .null,
                "encrypted_content": .string(result.encryptedContent),
                "type": .string("web_search_result")
            ])
        }

        var payload: [String: JSONValue] = [
            "type": .string("web_search_tool_result"),
            "tool_use_id": .string(part.toolCallId),
            "content": .array(mapped)
        ]
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    case "tool_search_tool_regex", "tool_search_tool_bm25":
        guard case .json(let value, _) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let toolReferences = try await validateTypes(
            ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicToolSearchRegex20251119OutputSchema)
        )

        let mapped = toolReferences.map { reference in
            JSONValue.object([
                "type": .string("tool_reference"),
                "tool_name": .string(reference.toolName)
            ])
        }

        var payload: [String: JSONValue] = [
            "type": .string("tool_search_tool_result"),
            "tool_use_id": .string(part.toolCallId),
            "content": .object([
                "type": .string("tool_search_tool_search_result"),
                "tool_references": .array(mapped)
            ])
        ]
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    default:
        warnings.append(.other(message: "provider executed tool result for tool \(part.toolName) is not supported"))
    }
}

private func jsonString(from value: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw UnsupportedFunctionalityError(functionality: "JSON serialization")
    }
    return string
}

private func stringifyJSONValue(_ value: JSONValue) -> String {
    (try? jsonString(from: value)) ?? "null"
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

private extension LanguageModelV3Message {
    enum RoleVariant {
        case system
        case user
        case assistant
        case tool
    }

    var roleVariant: RoleVariant {
        switch self {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        case .tool:
            return .tool
        }
    }
}
