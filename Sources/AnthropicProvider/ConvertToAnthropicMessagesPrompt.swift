import Foundation
import AISDKProvider
import AISDKProviderUtils

struct AnthropicPromptConversionResult: Sendable {
    let prompt: AnthropicMessagesPrompt
    let betas: Set<String>
}

func convertToAnthropicMessagesPrompt(
    prompt: LanguageModelV4Prompt,
    sendReasoning: Bool,
    toolNameMapping: AnthropicToolNameMapping = .init(),
    warnings: inout [SharedV4Warning],
    cacheControlValidator: CacheControlValidator? = nil,
    toolsetNames: [String: String] = [:]
) async throws -> AnthropicPromptConversionResult {
    let blocks = groupIntoAnthropicBlocks(prompt)
    let validator = cacheControlValidator ?? CacheControlValidator()
    var system: [JSONValue]?
    var messages: [AnthropicMessage] = []
    var betas = Set<String>()
    var lastUserMessageIndex = -1

    for (blockIndex, block) in blocks.enumerated() {
        switch block {
        case .system(let systemMessages):
            var converted: [(content: [JSONValue], clearAt: String?, effort: String?, toolChangeCount: Int)] = []
            for case let .system(text, providerOptions) in systemMessages {
                let options = try await parseProviderOptions(
                    provider: "anthropic",
                    providerOptions: providerOptions,
                    schema: anthropicSystemMessageProviderOptionsSchema
                )
                let clearAt = options?.clearAt
                let effort = options?.effort?.rawValue
                let toolChanges = options?.toolChanges ?? []
                var content: [JSONValue] = []
                if !text.isEmpty || (toolChanges.isEmpty && clearAt == nil && effort == nil) {
                    var payload: [String: JSONValue] = ["type": .string("text"), "text": .string(text)]
                    payload["cache_control"] = cacheControlJSON(from: validator.getCacheControl(
                        providerOptions,
                        context: .init(type: "system message", canCache: true)
                    ))
                    content.append(.object(payload))
                }
                for toolChange in toolChanges {
                    content.append(.object([
                        "type": .string(toolChange.type),
                        "tool": .object([
                            "type": .string("tool_reference"),
                            "name": .string(toolNameMapping.toProviderToolName(toolChange.toolName)),
                        ]),
                    ]))
                }
                converted.append((content, clearAt, effort, toolChanges.count))
            }

            let toolChangeCount = converted.reduce(0) { $0 + $1.toolChangeCount }
            let hasInlineOptions = converted.contains { $0.clearAt != nil || $0.effort != nil }
            if blockIndex == 0 || (system == nil && toolChangeCount == 0 && !hasInlineOptions) {
                if toolChangeCount > 0 {
                    warnings.append(.other(message: "tool changes on the initial system message are not supported by Anthropic. Configure the initial tool set via the tools option instead. The tool changes have been ignored."))
                }
                for message in converted {
                    if message.content.isEmpty && message.clearAt == nil, let effort = message.effort {
                        messages.append(AnthropicMessage(role: "system", content: [], outputConfig: ["effort": .string(effort)]))
                        betas.insert("mid-conversation-output-config-2026-07-01")
                    } else if message.clearAt != nil || message.effort != nil {
                        warnings.append(.other(message: "clearAt and effort on this initial system message are not supported by Anthropic. Use a separate effort-only system message with empty content to set effort. These options have been ignored."))
                    }
                }
                system = converted.flatMap(\.content).filter { $0["type"] == .string("text") }
            } else {
                betas.insert("mid-conversation-system-2026-04-07")
                for message in converted {
                    messages.append(AnthropicMessage(
                        role: "system",
                        content: message.content,
                        clearAt: message.clearAt,
                        outputConfig: message.effort.map { ["effort": .string($0)] }
                    ))
                    if message.toolChangeCount > 0 { betas.insert("mid-conversation-tool-changes-2026-07-01") }
                    if message.clearAt != nil { betas.insert("mid-conversation-system-clear-at-2026-08-21") }
                    if message.effort != nil { betas.insert("mid-conversation-output-config-2026-07-01") }
                }
            }

        case .user(let userMessages):
            var content: [JSONValue] = []
            for message in userMessages {
                switch message {
                case let .user(parts, providerOptions):
                    if !parts.isEmpty { lastUserMessageIndex = messages.count }
                    try await appendUserMessageParts(
                        parts,
                        messageProviderOptions: providerOptions,
                        anthropicContent: &content,
                        betas: &betas,
                        cacheControlValidator: validator
                    )
                case let .tool(parts, providerOptions):
                    try appendToolMessageParts(
                        parts,
                        messageProviderOptions: providerOptions,
                        anthropicContent: &content,
                        betas: &betas,
                        cacheControlValidator: validator,
                        toolsetNames: toolsetNames,
                        warnings: &warnings
                    )
                default:
                    break
                }
            }
            messages.append(AnthropicMessage(role: "user", content: content))

        case .assistant(let assistantMessages):
            var content: [JSONValue] = []
            var mcpToolUseIds = Set<String>()
            for (messageIndex, message) in assistantMessages.enumerated() {
                guard case let .assistant(parts, providerOptions) = message else { continue }
                try await appendAssistantMessageParts(
                    parts,
                    messageProviderOptions: providerOptions,
                    isLastBlock: blockIndex == blocks.count - 1,
                    isLastMessage: messageIndex == assistantMessages.count - 1,
                    anthropicContent: &content,
                    betas: &betas,
                    mcpToolUseIds: &mcpToolUseIds,
                    sendReasoning: sendReasoning,
                    toolNameMapping: toolNameMapping,
                    toolsetNames: toolsetNames,
                    cacheControlValidator: validator,
                    warnings: &warnings
                )
            }
            if !content.isEmpty {
                messages.append(AnthropicMessage(role: "assistant", content: moveAnthropicToolUseBlocksToEnd(content)))
            }
        }
    }

    let codeExecutionIds = Set(messages.filter { $0.role == "assistant" }.flatMap(\.content).compactMap { part -> String? in
        guard part["type"] == .string("server_tool_use"), part["name"] == .string("code_execution") else { return nil }
        return part["id"]?.stringValue
    })
    var warnedToolCallIds = Set<String>()
    for index in messages.indices where index < lastUserMessageIndex && messages[index].role == "assistant" {
        for partIndex in messages[index].content.indices {
            guard case .object(var part) = messages[index].content[partIndex],
                  case .object(let caller) = part["caller"],
                  caller["type"] != .string("direct"),
                  let toolId = caller["tool_id"]?.stringValue,
                  !codeExecutionIds.contains(toolId),
                  let toolCallId = (part["id"] ?? part["tool_use_id"])?.stringValue else { continue }
            part.removeValue(forKey: "caller")
            messages[index].content[partIndex] = .object(part)
            if warnedToolCallIds.insert(toolCallId).inserted {
                warnings.append(.other(message: "Omitted caller metadata for tool \(toolCallId) because source code execution tool \(toolId) is missing from the conversation history."))
            }
        }
    }

    return AnthropicPromptConversionResult(prompt: .init(system: system, messages: messages), betas: betas)
}

private enum AnthropicPromptBlock {
    case system([LanguageModelV4Message])
    case assistant([LanguageModelV4Message])
    case user([LanguageModelV4Message])
}

private func groupIntoAnthropicBlocks(_ prompt: LanguageModelV4Prompt) -> [AnthropicPromptBlock] {
    var blocks: [AnthropicPromptBlock] = []
    for message in prompt {
        switch message {
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
    _ parts: [LanguageModelV4UserMessagePart],
    messageProviderOptions: SharedV4ProviderOptions?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    cacheControlValidator: CacheControlValidator
) async throws {
    for (index, part) in parts.enumerated() {
        let providerOptions: SharedV4ProviderOptions? = switch part {
        case .text(let part): part.providerOptions
        case .file(let part): part.providerOptions
        }
        let cacheControl = cacheControlValidator.getCacheControl(providerOptions, context: .init(type: "user message part", canCache: true))
            ?? (index == parts.count - 1
                ? cacheControlValidator.getCacheControl(messageProviderOptions, context: .init(type: "user message", canCache: true))
                : nil)
        var payload: [String: JSONValue]
        switch part {
        case .text(let part):
            payload = ["type": .string("text"), "text": .string(part.text)]
        case .file(let part):
            payload = try await userFilePayload(part, betas: &betas)
        }
        if payload["type"] != .string("container_upload") {
            payload["cache_control"] = cacheControlJSON(from: cacheControl)
        }
        anthropicContent.append(.object(payload))
    }
}

private func userFilePayload(_ part: LanguageModelV4FilePart, betas: inout Set<String>) async throws -> [String: JSONValue] {
    if case .reference(let reference) = part.data {
        let fileId = try resolveProviderReference(reference: reference, provider: "anthropic")
        betas.insert("files-api-2025-04-14")
        let options = try await parseProviderOptions(provider: "anthropic", providerOptions: part.providerOptions, schema: anthropicFilePartProviderOptionsSchema)
        if options?.containerUpload == true {
            return ["type": .string("container_upload"), "file_id": .string(fileId)]
        }
        return [
            "type": .string(getTopLevelMediaType(part.mediaType) == "image" ? "image" : "document"),
            "source": .object(["type": .string("file"), "file_id": .string(fileId)]),
        ]
    }

    let isText: Bool
    if case .text = part.data { isText = true } else { isText = false }
    if !isText && getTopLevelMediaType(part.mediaType) == "image" {
        return ["type": .string("image"), "source": try fileSource(part, text: false)]
    }
    let mediaType: String
    switch part.data {
    case .data where getTopLevelMediaType(part.mediaType) == "application",
         .base64 where getTopLevelMediaType(part.mediaType) == "application":
        mediaType = try resolveFullMediaType(part: part)
    default:
        mediaType = part.mediaType
    }
    guard isText || mediaType == "application/pdf" || mediaType == "text/plain" else {
        throw UnsupportedFunctionalityError(functionality: "media type: \(part.mediaType)")
    }
    if !isText && mediaType == "application/pdf" { betas.insert("pdfs-2024-09-25") }
    let options = try await parseProviderOptions(provider: "anthropic", providerOptions: part.providerOptions, schema: anthropicFilePartProviderOptionsSchema)
    var payload: [String: JSONValue] = [
        "type": .string("document"),
        "source": try fileSource(part, text: isText || part.mediaType == "text/plain"),
    ]
    if let title = options?.title ?? part.filename { payload["title"] = .string(title) }
    if let context = options?.context, !context.isEmpty { payload["context"] = .string(context) }
    if options?.citations?.enabled == true { payload["citations"] = .object(["enabled": .bool(true)]) }
    return payload
}

private func fileSource(_ part: LanguageModelV4FilePart, text: Bool) throws -> JSONValue {
    switch part.data {
    case let .url(url, originalUrl):
        return .object(["type": .string("url"), "url": .string(originalUrl ?? url.absoluteString)])
    case .text(let value):
        return .object(["type": .string("text"), "media_type": .string("text/plain"), "data": .string(value)])
    case .data(let data):
        if text {
            return .object(["type": .string("text"), "media_type": .string("text/plain"), "data": .string(decodeUTF8(data))])
        }
        return .object(["type": .string("base64"), "media_type": .string(try resolveFullMediaType(part: part)), "data": .string(data.base64EncodedString())])
    case .base64(let data):
        if text {
            return .object(["type": .string("text"), "media_type": .string("text/plain"), "data": .string(decodeUTF8(try convertBase64ToData(data)))])
        }
        return .object(["type": .string("base64"), "media_type": .string(try resolveFullMediaType(part: part)), "data": .string(data)])
    case .reference(let reference):
        return .object(["type": .string("file"), "file_id": .string(try resolveProviderReference(reference: reference, provider: "anthropic"))])
    }
}

private func appendToolMessageParts(
    _ parts: [LanguageModelV4ToolMessagePart],
    messageProviderOptions: SharedV4ProviderOptions?,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    cacheControlValidator: CacheControlValidator,
    toolsetNames: [String: String],
    warnings: inout [SharedV4Warning]
) throws {
    for (index, item) in parts.enumerated() {
        guard case .toolResult(let part) = item else { continue }
        let cacheControl = cacheControlValidator.getCacheControl(part.providerOptions, context: .init(type: "tool result part", canCache: true))
            ?? cacheControlValidator.getCacheControl(part.output.providerOptions, context: .init(type: "tool result output", canCache: true))
            ?? (index == parts.count - 1
                ? cacheControlValidator.getCacheControl(messageProviderOptions, context: .init(type: "tool result message", canCache: true))
                : nil)
        var payload: [String: JSONValue] = ["type": .string("tool_result"), "tool_use_id": .string(part.toolCallId)]
        switch part.output {
        case .content(let items):
            payload["content"] = .array(try items.compactMap { item in
                switch item {
                case .text(let text, _):
                    return .object(["type": .string("text"), "text": .string(text)])
                case let .file(data, mediaType, filename, providerOptions):
                    let file = LanguageModelV4FilePart(data: data, mediaType: mediaType, filename: filename, providerOptions: providerOptions)
                    let isImage = getTopLevelMediaType(mediaType) == "image"
                    switch data {
                    case .reference:
                        betas.insert("files-api-2025-04-14")
                    case .url:
                        break
                    case .data, .base64:
                        if !isImage {
                            guard try resolveFullMediaType(part: file) == "application/pdf" else {
                                warnings.append(.other(message: "unsupported tool content part type: file with media type: \(mediaType)"))
                                return nil
                            }
                            betas.insert("pdfs-2024-09-25")
                        }
                    case .text:
                        warnings.append(.other(message: "unsupported tool content part type: file with data type: text"))
                        return nil
                    }
                    return .object(["type": .string(isImage ? "image" : "document"), "source": try fileSource(file, text: false)])
                case .custom(let providerOptions):
                    if providerOptions?["anthropic"]?["type"] == .string("tool-reference") {
                        var reference: [String: JSONValue] = ["type": .string("tool_reference")]
                        reference["tool_name"] = providerOptions?["anthropic"]?["toolName"]
                        return .object(reference)
                    }
                    warnings.append(.other(message: "unsupported custom tool content part"))
                    return nil
                }
            })
        case .text(let value, _), .errorText(let value, _):
            payload["content"] = .string(value)
        case .executionDenied(let reason, _):
            payload["content"] = .string(reason ?? "Tool call execution denied.")
        case .json(let value, _), .errorJson(let value, _):
            payload["content"] = .string(try jsonString(from: value))
        }
        if part.output.isError { payload["is_error"] = .bool(true) }
        payload["toolset_name"] = toolsetName(part.toolName, providerOptions: part.providerOptions, toolsetNames: toolsetNames).map(JSONValue.string)
        payload["cache_control"] = cacheControlJSON(from: cacheControl)
        anthropicContent.append(.object(payload))
    }
}

private func appendAssistantMessageParts(
    _ parts: [LanguageModelV4MessagePart],
    messageProviderOptions: SharedV4ProviderOptions?,
    isLastBlock: Bool,
    isLastMessage: Bool,
    anthropicContent: inout [JSONValue],
    betas: inout Set<String>,
    mcpToolUseIds: inout Set<String>,
    sendReasoning: Bool,
    toolNameMapping: AnthropicToolNameMapping,
    toolsetNames: [String: String],
    cacheControlValidator: CacheControlValidator,
    warnings: inout [SharedV4Warning]
) async throws {
    for (index, part) in parts.enumerated() {
        let isLastPart = index == parts.count - 1
        let cacheControl = cacheControlValidator.getCacheControl(part.providerOptions, context: .init(type: "assistant message part", canCache: true))
            ?? (isLastPart
                ? cacheControlValidator.getCacheControl(messageProviderOptions, context: .init(type: "assistant message", canCache: true))
                : nil)
        let cacheControlJSON = cacheControlJSON(from: cacheControl)
        switch part {
        case .text(let part):
            let metadata = part.providerOptions?["anthropic"]
            var payload: [String: JSONValue]
            if metadata?["type"] == .string("compaction") {
                if part.text.isEmpty { continue }
                payload = ["type": .string("compaction"), "content": .string(part.text)]
                if let signature = metadata?["signature"]?.stringValue {
                    payload["signature"] = .string(signature)
                    betas.insert("compact-2026-09-04")
                }
            } else {
                payload = [
                    "type": .string("text"),
                    "text": .string(isLastBlock && isLastMessage && isLastPart ? part.text.trimmingCharacters(in: assistantPrefillWhitespace) : part.text),
                ]
                if let citations = metadata?["citations"], citations != .null { payload["citations"] = citations }
            }
            payload["cache_control"] = cacheControlJSON
            anthropicContent.append(.object(payload))

        case .reasoning(let part):
            guard sendReasoning else {
                warnings.append(.other(message: "sending reasoning content is disabled for this model"))
                continue
            }
            let metadata = try await parseProviderOptions(provider: "anthropic", providerOptions: part.providerOptions, schema: anthropicReasoningMetadataSchema)
            if let signature = metadata?.signature {
                _ = cacheControlValidator.getCacheControl(part.providerOptions, context: .init(type: "thinking block", canCache: false))
                anthropicContent.append(.object(["type": .string("thinking"), "thinking": .string(part.text), "signature": .string(signature)]))
            } else if let redacted = metadata?.redactedData {
                _ = cacheControlValidator.getCacheControl(part.providerOptions, context: .init(type: "redacted thinking block", canCache: false))
                anthropicContent.append(.object(["type": .string("redacted_thinking"), "data": .string(redacted)]))
            } else {
                warnings.append(.other(message: "unsupported reasoning metadata"))
            }

        case .custom(let part):
            guard part.kind == "anthropic.fallback" else { continue }
            let validation = await safeValidateTypes(ValidateTypesOptions(
                value: jsonValueToFoundation(part.providerOptions?["anthropic"].map(JSONValue.object) ?? .null),
                schema: anthropicFallbackContentSchema
            ))
            guard case .success(let metadata, _) = validation else {
                warnings.append(.other(message: "anthropic fallback metadata must include from.model and to.model"))
                continue
            }
            betas.insert("server-side-fallback-2026-06-01")
            anthropicContent.append(.object([
                "type": .string("fallback"),
                "from": .object(["model": .string(metadata.from.model)]),
                "to": .object(["model": .string(metadata.to.model)]),
            ]))

        case .toolCall(let part):
            let caller = anthropicCaller(part.providerOptions)
            var payload: [String: JSONValue]
            if part.providerExecuted == true {
                let name = toolNameMapping.toProviderToolName(part.toolName)
                if part.providerOptions?["anthropic"]?["type"] == .string("mcp-tool-use") {
                    mcpToolUseIds.insert(part.toolCallId)
                    guard let server = part.providerOptions?["anthropic"]?["serverName"]?.stringValue else {
                        warnings.append(.other(message: "mcp tool use server name is required and must be a string"))
                        continue
                    }
                    payload = ["type": .string("mcp_tool_use"), "id": .string(part.toolCallId), "name": .string(part.toolName), "input": part.input, "server_name": .string(server)]
                } else {
                    var input = part.input
                    var wireName = name
                    if name == "code_execution", case .object(var object) = input, let type = object["type"]?.stringValue,
                       ["bash_code_execution", "text_editor_code_execution", "programmatic-tool-call"].contains(type) {
                        object.removeValue(forKey: "type")
                        input = .object(object)
                        if type != "programmatic-tool-call" { wireName = type }
                    } else if name == "advisor" {
                        input = .object([:])
                    } else if !["code_execution", "web_fetch", "web_search", "tool_search_tool_regex", "tool_search_tool_bm25"].contains(name) {
                        warnings.append(.other(message: "provider executed tool call for tool \(part.toolName) is not supported"))
                        continue
                    }
                    payload = ["type": .string("server_tool_use"), "id": .string(part.toolCallId), "name": .string(wireName), "input": input]
                    payload["caller"] = caller
                }
            } else {
                let input: [String: JSONValue]
                if case .object(let object) = part.input { input = object } else { input = ["rawInvalidInput": part.input] }
                payload = ["type": .string("tool_use"), "id": .string(part.toolCallId), "name": .string(part.toolName), "input": .object(input)]
                if let toolset = toolsetName(part.toolName, providerOptions: part.providerOptions, toolsetNames: toolsetNames) {
                    let action = input["action"]?.stringValue
                    if action == nil { warnings.append(.other(message: "toolset tool call for tool \(part.toolName) is missing the action")) }
                    payload["name"] = .string(action ?? toolset)
                    payload["toolset_name"] = .string(toolset)
                }
                payload["caller"] = caller
            }
            payload["cache_control"] = cacheControlJSON
            anthropicContent.append(.object(payload))

        case .toolResult(let part):
            try await appendAssistantToolResult(
                part,
                cacheControlJSON: cacheControlJSON,
                anthropicContent: &anthropicContent,
                mcpToolUseIds: mcpToolUseIds,
                toolNameMapping: toolNameMapping,
                warnings: &warnings
            )
        case .file, .reasoningFile:
            break
        }
    }
}

private func appendAssistantToolResult(
    _ part: LanguageModelV4ToolResultPart,
    cacheControlJSON: JSONValue?,
    anthropicContent: inout [JSONValue],
    mcpToolUseIds: Set<String>,
    toolNameMapping: AnthropicToolNameMapping,
    warnings: inout [SharedV4Warning]
) async throws {
    let name = toolNameMapping.toProviderToolName(part.toolName)
    let output = part.output
    let caller = anthropicCaller(part.providerOptions)
    func unsupportedOutput() -> SharedV4Warning {
        .other(message: "provider executed tool result output type \(output.type) for tool \(part.toolName) is not supported")
    }
    var blockType: String
    var content: JSONValue
    var attachCaller = false

    if mcpToolUseIds.contains(part.toolCallId) {
        guard let value = output.jsonValue else {
            warnings.append(unsupportedOutput())
            return
        }
        var payload: [String: JSONValue] = [
            "type": .string("mcp_tool_result"), "tool_use_id": .string(part.toolCallId),
            "is_error": .bool(output.isError), "content": value,
        ]
        payload["cache_control"] = cacheControlJSON
        anthropicContent.append(.object(payload))
        warnings.append(.other(message: "provider executed tool result for tool \(part.toolName) is not supported"))
        return
    }

    switch name {
    case "code_execution":
        if output.isError {
            let value: JSONValue
            switch output {
            case .errorText(let text, _): value = .string(text)
            case .errorJson(let json, _): value = json
            default: value = .null
            }
            let error = errorObject(value)
            let legacy = error["type"] == .string("code_execution_tool_result_error")
            blockType = legacy ? "code_execution_tool_result" : "bash_code_execution_tool_result"
            content = .object([
                "type": .string(legacy ? "code_execution_tool_result_error" : "bash_code_execution_tool_result_error"),
                "error_code": errorCode(value, fallback: "unknown"),
            ])
        } else {
            guard case .json(let value, _) = output else {
                warnings.append(unsupportedOutput())
                return
            }
            guard let type = value["type"]?.stringValue else {
                warnings.append(.other(message: "provider executed tool result output value is not a valid code execution result for tool \(part.toolName)"))
                return
            }
            if type == "code_execution_result" {
                let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicCodeExecution20250522OutputSchema))
                blockType = "code_execution_tool_result"
                content = try encodeJSONValue(parsed)
            } else if type == "encrypted_code_execution_result" {
                let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicCodeExecution20260120OutputSchema))
                guard case .object(var object) = parsed else { return }
                object["content"] = object["content"] ?? .array([])
                blockType = "code_execution_tool_result"
                content = .object(object)
            } else {
                let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicCodeExecution20250825OutputSchema))
                content = try encodeJSONValue(parsed)
                switch parsed {
                case .codeExecutionResult: blockType = "code_execution_tool_result"
                case .bashCodeExecutionResult: blockType = "bash_code_execution_tool_result"
                case .toolError(let error) where error.type == "bash_code_execution_tool_result_error": blockType = "bash_code_execution_tool_result"
                case .textEditorViewResult(let result):
                    blockType = "text_editor_code_execution_tool_result"
                    content = .object([
                        "type": .string(result.type), "content": .string(result.content), "file_type": .string(result.fileType),
                        "num_lines": result.numLines.map { .number(Double($0)) } ?? .null,
                        "start_line": result.startLine.map { .number(Double($0)) } ?? .null,
                        "total_lines": result.totalLines.map { .number(Double($0)) } ?? .null,
                    ])
                case .textEditorStrReplaceResult(let result):
                    blockType = "text_editor_code_execution_tool_result"
                    content = .object([
                        "type": .string(result.type), "lines": result.lines.map { .array($0.map(JSONValue.string)) } ?? .null,
                        "new_lines": result.newLines.map { .number(Double($0)) } ?? .null,
                        "new_start": result.newStart.map { .number(Double($0)) } ?? .null,
                        "old_lines": result.oldLines.map { .number(Double($0)) } ?? .null,
                        "old_start": result.oldStart.map { .number(Double($0)) } ?? .null,
                    ])
                default: blockType = "text_editor_code_execution_tool_result"
                }
            }
        }

    case "web_fetch":
        blockType = "web_fetch_tool_result"
        attachCaller = true
        if case .errorJson(let value, _) = output {
            content = .object(["type": .string("web_fetch_tool_result_error"), "error_code": errorCode(value, fallback: "unavailable")])
        } else if case .json(let value, _) = output {
            let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicWebFetch20250910OutputSchema))
            var document: [String: JSONValue] = [
                "type": .string("document"), "title": parsed.content.title.map(JSONValue.string) ?? .null,
                "source": .object(["type": .string(parsed.content.source.type), "media_type": .string(parsed.content.source.mediaType), "data": .string(parsed.content.source.data)]),
            ]
            if let citations = parsed.content.citations { document["citations"] = .object(["enabled": .bool(citations.enabled)]) }
            content = .object([
                "type": .string("web_fetch_result"), "url": .string(parsed.url),
                "retrieved_at": parsed.retrievedAt.map(JSONValue.string) ?? .null, "content": .object(document),
            ])
        } else {
            warnings.append(unsupportedOutput())
            return
        }

    case "web_search":
        blockType = "web_search_tool_result"
        attachCaller = true
        if case .errorJson(let value, _) = output {
            content = .object(["type": .string("web_search_tool_result_error"), "error_code": errorCode(value, fallback: "unavailable")])
        } else if case .json(let value, _) = output {
            let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicWebSearch20250305OutputSchema))
            content = .array(parsed.map { result in
                .object([
                    "url": .string(result.url), "title": result.title.map(JSONValue.string) ?? .null,
                    "page_age": result.pageAge.map(JSONValue.string) ?? .null,
                    "encrypted_content": .string(result.encryptedContent), "type": .string(result.type),
                ])
            })
        } else {
            warnings.append(unsupportedOutput())
            return
        }

    case "tool_search_tool_regex", "tool_search_tool_bm25":
        blockType = "tool_search_tool_result"
        if case .errorJson(let value, _) = output {
            content = .object(["type": .string("tool_search_tool_result_error"), "error_code": errorCode(value, fallback: "unavailable")])
        } else if case .json(let value, _) = output {
            if value["type"] == .string("tool_search_tool_result_error") {
                content = .object(["type": .string("tool_search_tool_result_error"), "error_code": errorCode(value, fallback: "unavailable")])
            } else {
                let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicToolSearchRegex20251119OutputSchema))
                content = .object([
                    "type": .string("tool_search_tool_search_result"),
                    "tool_references": .array(parsed.map { .object(["type": .string("tool_reference"), "tool_name": .string($0.toolName)]) }),
                ])
            }
        } else {
            warnings.append(unsupportedOutput())
            return
        }

    case "advisor":
        guard let value = output.jsonValue else {
            warnings.append(unsupportedOutput())
            return
        }
        let parsed = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: anthropicAdvisor20260301OutputSchema))
        guard let type = parsed["type"]?.stringValue else { return }
        var object: [String: JSONValue] = ["type": .string(type)]
        switch type {
        case "advisor_result": object["text"] = parsed["text"]
        case "advisor_redacted_result": object["encrypted_content"] = parsed["encryptedContent"]
        default: object["error_code"] = parsed["errorCode"]
        }
        if type == "advisor_result" || type == "advisor_redacted_result" { object["stop_reason"] = parsed["stopReason"] }
        blockType = "advisor_tool_result"
        content = .object(object)

    default:
        warnings.append(.other(message: "provider executed tool result for tool \(part.toolName) is not supported"))
        return
    }
    var payload: [String: JSONValue] = ["type": .string(blockType), "tool_use_id": .string(part.toolCallId), "content": content]
    payload["cache_control"] = cacheControlJSON
    if attachCaller { payload["caller"] = caller }
    anthropicContent.append(.object(payload))
}

private func moveAnthropicToolUseBlocksToEnd(_ content: [JSONValue]) -> [JSONValue] {
    var result: [JSONValue] = []
    var segment: [JSONValue] = []
    func flush() {
        result.append(contentsOf: segment.filter { $0["type"] != .string("tool_use") })
        result.append(contentsOf: segment.filter { $0["type"] == .string("tool_use") })
        segment.removeAll(keepingCapacity: true)
    }
    for part in content {
        if ["thinking", "redacted_thinking", "fallback"].contains(part["type"]?.stringValue ?? "") {
            flush()
            result.append(part)
        } else {
            segment.append(part)
        }
    }
    flush()
    return result
}

private func toolsetName(_ name: String, providerOptions: SharedV4ProviderOptions?, toolsetNames: [String: String]) -> String? {
    toolsetNames[name] ?? providerOptions?["anthropic"]?["toolsetName"]?.stringValue
}

private func anthropicCaller(_ providerOptions: SharedV4ProviderOptions?) -> JSONValue? {
    guard case .object(let caller) = providerOptions?["anthropic"]?["caller"], let type = caller["type"]?.stringValue else { return nil }
    if ["code_execution_20250825", "code_execution_20260120"].contains(type), let id = caller["toolId"]?.stringValue, !id.isEmpty {
        return .object(["type": .string(type), "tool_id": .string(id)])
    }
    return type == "direct" ? .object(["type": .string("direct")]) : nil
}

private func errorCode(_ value: JSONValue, fallback: String) -> JSONValue {
    guard let code = errorObject(value)["errorCode"], code != .null else { return .string(fallback) }
    return code
}

private func errorObject(_ value: JSONValue) -> [String: JSONValue] {
    if case .object(let object) = value { return object }
    if case .string(let text) = value, let data = text.data(using: .utf8),
       let parsed = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let object) = parsed { return object }
    return [:]
}

// Foundation whitespace differs from ECMAScript trim at U+0085 and U+FEFF.
private let assistantPrefillWhitespace = CharacterSet(charactersIn: "\u{0009}\u{000a}\u{000b}\u{000c}\u{000d}\u{0020}\u{00a0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200a}\u{2028}\u{2029}\u{202f}\u{205f}\u{3000}\u{feff}")

private func decodeUTF8(_ data: Data) -> String {
    // TextDecoder omits the initial UTF-8 byte-order mark.
    let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
    return String(decoding: bytes, as: UTF8.self)
}

private func encodeJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
}

private func jsonString(from value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func cacheControlJSON(from cacheControl: AnthropicCacheControl?) -> JSONValue? {
    guard let cacheControl else { return nil }
    var payload = cacheControl.additionalFields
    if let type = cacheControl.type { payload["type"] = .string(type) }
    if let ttl = cacheControl.ttl { payload["ttl"] = .string(ttl.rawValue) }
    return .object(payload)
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

private extension LanguageModelV4MessagePart {
    var providerOptions: SharedV4ProviderOptions? {
        switch self {
        case .text(let part): part.providerOptions
        case .file(let part): part.providerOptions
        case .custom(let part): part.providerOptions
        case .reasoning(let part): part.providerOptions
        case .reasoningFile(let part): part.providerOptions
        case .toolCall(let part): part.providerOptions
        case .toolResult(let part): part.providerOptions
        }
    }
}

private extension LanguageModelV4ToolResultContentPart {
    var providerOptions: SharedV4ProviderOptions? {
        switch self {
        case .text(_, let options), .file(_, _, _, let options), .custom(let options): options
        }
    }
}

private extension LanguageModelV4ToolResultOutput {
    var providerOptions: SharedV4ProviderOptions? {
        switch self {
        case .text(_, let options), .json(_, let options), .executionDenied(_, let options), .errorText(_, let options), .errorJson(_, let options): options
        case .content(let parts): parts.first { $0.providerOptions != nil }?.providerOptions
        }
    }

    var type: String {
        switch self {
        case .text: "text"
        case .json: "json"
        case .executionDenied: "execution-denied"
        case .errorText: "error-text"
        case .errorJson: "error-json"
        case .content: "content"
        }
    }

    var isError: Bool {
        switch self {
        case .errorText, .errorJson: true
        default: false
        }
    }

    var jsonValue: JSONValue? {
        switch self {
        case .json(let value, _), .errorJson(let value, _): value
        default: nil
        }
    }
}
