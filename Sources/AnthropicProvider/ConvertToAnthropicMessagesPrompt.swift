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
    warnings: inout [LanguageModelV3CallWarning]
) async throws -> AnthropicPromptConversionResult {
    let blocks = groupIntoAnthropicBlocks(prompt)

    var systemContent: [JSONValue]? = nil
    var messages: [AnthropicMessage] = []
    var betas = Set<String>()

    for (blockIndex, block) in blocks.enumerated() {
        let isLastBlock = blockIndex == blocks.count - 1

        switch block {
        case .system(let systemMessages):
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
                    sendReasoning: sendReasoning,
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
        let base64: String
        switch filePart.data {
        case .data(let data):
            base64 = convertDataToBase64(data)
        case .base64(let string):
            base64 = string
        case .url(let url):
            throw UnsupportedFunctionalityError(functionality: "URL-based PDFs", message: url.absoluteString)
        }

        var payload: [String: JSONValue] = [
            "type": .string("document"),
            "source": .object([
                "type": .string("base64"),
                "media_type": .string("application/pdf"),
                "data": .string(base64)
            ])
        ]
        if let title { payload["title"] = .string(title) }
        if let context { payload["context"] = .string(context) }
        if citationsEnabled { payload["citations"] = .object(["enabled": .bool(true)]) }
        if let cacheControlJSON { payload["cache_control"] = cacheControlJSON }
        anthropicContent.append(.object(payload))

    case "text/plain":
        betas.insert("pdfs-2024-09-25")
        let text: String
        switch filePart.data {
        case .data(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "text/plain encoding", message: "Expected UTF-8 data")
            }
            text = string
        case .base64(let base64):
            let data = try convertBase64ToData(base64)
            guard let string = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "text/plain encoding", message: "Expected UTF-8 data")
            }
            text = string
        case .url(let url):
            throw UnsupportedFunctionalityError(functionality: "URL-based text documents", message: url.absoluteString)
        }

        var payload: [String: JSONValue] = [
            "type": .string("document"),
            "source": .object([
                "type": .string("text"),
                "media_type": .string("text/plain"),
                "data": .string(text)
            ])
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
    _ parts: [LanguageModelV3ToolResultPart],
    messageProviderOptions: SharedV3ProviderOptions?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    warnings: inout [LanguageModelV3CallWarning]
) async throws {
    for (index, part) in parts.enumerated() {
        let isLastPart = index == parts.count - 1
        let cacheControl = getAnthropicCacheControl(from: part.providerOptions) ?? (isLastPart ? getAnthropicCacheControl(from: messageProviderOptions) : nil)
        let cacheControlJSON = cacheControlJSON(from: cacheControl)

        var payload: [String: JSONValue] = [
            "type": .string("tool_result"),
            "tool_use_id": .string(part.toolCallId)
        ]

        switch part.output {
        case .content(let items):
            let mapped = try items.map { item -> JSONValue in
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

        case .text(let value):
            payload["content"] = .string(value)
        case .errorText(let value):
            payload["content"] = .string(value)
            payload["is_error"] = .bool(true)
        case .executionDenied(let reason):
            payload["content"] = .string(reason ?? "Tool execution denied.")
        case .json(let value), .errorJson(let value):
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
    sendReasoning: Bool,
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
                switch toolCallPart.toolName {
                case "code_execution":
                    betas.insert("code-execution-2025-05-22")
                case "web_fetch":
                    betas.insert("web-fetch-2025-09-10")
                case "web_search":
                    break
                default:
                    warnings.append(.other(message: "provider executed tool call for tool \(toolCallPart.toolName) is not supported"))
                    continue
                }

                payload = [
                    "type": .string("server_tool_use"),
                    "id": .string(toolCallPart.toolCallId),
                    "name": .string(toolCallPart.toolName),
                    "input": .string(stringifyJSONValue(toolCallPart.input))
                ]
            } else {
                payload = [
                    "type": .string("tool_use"),
                    "id": .string(toolCallPart.toolCallId),
                    "name": .string(toolCallPart.toolName),
                    "input": .string(stringifyJSONValue(toolCallPart.input))
                ]
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
    warnings: inout [LanguageModelV3CallWarning]
) async throws {
    switch part.toolName {
    case "code_execution":
        guard case .json(let value) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let parsed = try await validateTypes(
            ValidateTypesOptions(value: value, schema: anthropicCodeExecution20250522OutputSchema)
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
        guard case .json(let value) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let parsed = try await validateTypes(
            ValidateTypesOptions(value: value, schema: anthropicWebFetch20250910OutputSchema)
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
        guard case .json(let value) = part.output else {
            warnings.append(.other(message: "provider executed tool result output type for tool \(part.toolName) is not supported"))
            return
        }

        let results = try await validateTypes(
            ValidateTypesOptions(value: value, schema: anthropicWebSearch20250305OutputSchema)
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
    var payload: [String: JSONValue] = [
        "type": .string(cacheControl.type)
    ]
    if let ttl = cacheControl.ttl {
        payload["ttl"] = .string(ttl.rawValue)
    }
    return .object(payload)
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
