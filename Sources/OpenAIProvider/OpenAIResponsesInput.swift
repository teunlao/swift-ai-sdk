import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesInputBuilder {
    static func makeInput(
        prompt: LanguageModelV3Prompt,
        providerOptionsName: String = "openai",
        toolNameMapping: OpenAIToolNameMapping = .init(),
        customProviderToolNames: Set<String> = [],
        systemMessageMode: OpenAIResponsesSystemMessageMode = .system,
        fileIdPrefixes: [String]? = ["file-"],
        store: Bool = true,
        hasConversation: Bool = false,
        hasPreviousResponseId: Bool = false,
        passThroughUnsupportedFiles: Bool = false,
        hasLocalShellTool: Bool = false,
        hasShellTool: Bool = false,
        hasApplyPatchTool: Bool = false
    ) async throws -> (input: OpenAIResponsesInput, warnings: [SharedV3Warning]) {
        try await makeInput(
            prompt: OpenAIResponsesPrompt(v3: prompt),
            providerOptionsName: providerOptionsName,
            toolNameMapping: toolNameMapping,
            customProviderToolNames: customProviderToolNames,
            systemMessageMode: systemMessageMode,
            fileIdPrefixes: fileIdPrefixes,
            store: store,
            hasConversation: hasConversation,
            hasPreviousResponseId: hasPreviousResponseId,
            passThroughUnsupportedFiles: passThroughUnsupportedFiles,
            hasLocalShellTool: hasLocalShellTool,
            hasShellTool: hasShellTool,
            hasApplyPatchTool: hasApplyPatchTool
        )
    }

    static func makeInput(
        prompt: LanguageModelV4Prompt,
        providerOptionsName: String = "openai",
        toolNameMapping: OpenAIToolNameMapping = .init(),
        customProviderToolNames: Set<String> = [],
        systemMessageMode: OpenAIResponsesSystemMessageMode = .system,
        fileIdPrefixes: [String]? = ["file-"],
        store: Bool = true,
        hasConversation: Bool = false,
        hasPreviousResponseId: Bool = false,
        passThroughUnsupportedFiles: Bool = false,
        hasLocalShellTool: Bool = false,
        hasShellTool: Bool = false,
        hasApplyPatchTool: Bool = false
    ) async throws -> (input: OpenAIResponsesInput, warnings: [SharedV3Warning]) {
        try await makeInput(
            prompt: OpenAIResponsesPrompt(v4: prompt, providerOptionsName: providerOptionsName),
            providerOptionsName: providerOptionsName,
            toolNameMapping: toolNameMapping,
            customProviderToolNames: customProviderToolNames,
            systemMessageMode: systemMessageMode,
            fileIdPrefixes: fileIdPrefixes,
            store: store,
            hasConversation: hasConversation,
            hasPreviousResponseId: hasPreviousResponseId,
            passThroughUnsupportedFiles: passThroughUnsupportedFiles,
            hasLocalShellTool: hasLocalShellTool,
            hasShellTool: hasShellTool,
            hasApplyPatchTool: hasApplyPatchTool
        )
    }

    private static func makeInput(
        prompt: OpenAIResponsesPrompt,
        providerOptionsName: String,
        toolNameMapping: OpenAIToolNameMapping,
        customProviderToolNames: Set<String>,
        systemMessageMode: OpenAIResponsesSystemMessageMode,
        fileIdPrefixes: [String]?,
        store: Bool,
        hasConversation: Bool,
        hasPreviousResponseId: Bool,
        passThroughUnsupportedFiles: Bool,
        hasLocalShellTool: Bool,
        hasShellTool: Bool,
        hasApplyPatchTool: Bool
    ) async throws -> (input: OpenAIResponsesInput, warnings: [SharedV3Warning]) {
        var items: [JSONValue] = []
        var warnings: [SharedV3Warning] = []
        var reasoningReferences: Set<String> = []
        var processedApprovalIds: Set<String> = []

        for message in prompt {
            switch message {
            case let .system(content, providerOptions):
                switch systemMessageMode {
                case .system:
                    items.append(systemItem(
                        role: "system",
                        content: content,
                        providerOptions: providerOptions,
                        providerOptionsName: providerOptionsName
                    ))
                case .developer:
                    items.append(systemItem(
                        role: "developer",
                        content: content,
                        providerOptions: providerOptions,
                        providerOptionsName: providerOptionsName
                    ))
                case .remove:
                    warnings.append(.other(message: "system messages are removed for this model"))
                }

            case let .user(parts, _):
                let content = try parts.enumerated().map { index, part in
                    try convertUserPart(
                        part,
                        index: index,
                        prefixes: fileIdPrefixes,
                        providerOptionsName: providerOptionsName,
                        passThroughUnsupportedFiles: passThroughUnsupportedFiles
                    )
                }

                items.append(.object([
                    "role": .string("user"),
                    "content": .array(content)
                ]))

            case let .assistant(parts, _):
                var reasoningMessages: [String: ReasoningAccumulator] = [:]

                for part in parts {
                    switch part {
                    case .text(let textPart):
                        let itemId = extractOpenAIStringOption(
                            from: textPart.providerOptions,
                            providerOptionsName: providerOptionsName,
                            key: "itemId"
                        )
                        let phase = extractOpenAIStringOption(
                            from: textPart.providerOptions,
                            providerOptionsName: providerOptionsName,
                            key: "phase"
                        )

                        if hasConversation, itemId != nil {
                            continue
                        }

                        if store, let itemId {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                            continue
                        }

                        var payload: [String: JSONValue] = [
                            "role": .string("assistant"),
                            "content": .array([
                                .object([
                                    "type": .string("output_text"),
                                    "text": .string(textPart.text)
                                ])
                            ])
                        ]

                        if let itemId {
                            payload["id"] = .string(itemId)
                        }
                        if let phase {
                            payload["phase"] = .string(phase)
                        }

                        items.append(.object(payload))

                    case .toolCall(let callPart):
                        let itemId =
                            extractOpenAIItemId(from: callPart.providerOptions, providerOptionsName: providerOptionsName)
                            ?? extractOpenAIItemId(from: callPart.providerMetadata, providerOptionsName: providerOptionsName)

                        if hasConversation, itemId != nil {
                            continue
                        }

                        if callPart.providerExecuted == true {
                            if store, let itemId {
                                items.append(.object([
                                    "type": .string("item_reference"),
                                    "id": .string(itemId)
                                ]))
                            }
                            continue
                        }

                        if hasPreviousResponseId, store, itemId != nil {
                            continue
                        }

                        if store, let itemId {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                            continue
                        }

                        let resolvedToolName = toolNameMapping.toProviderToolName(callPart.toolName)

                        if resolvedToolName == "tool_search" {
                            if store, let itemId {
                                items.append(.object([
                                    "type": .string("item_reference"),
                                    "id": .string(itemId)
                                ]))
                                continue
                            }

                            let parsedInput = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiToolSearchInputSchema)
                            )
                            let execution = parsedInput.callId != nil ? "client" : "server"
                            var payload: [String: JSONValue] = [
                                "type": .string("tool_search_call"),
                                "id": .string(itemId ?? callPart.toolCallId),
                                "execution": .string(execution),
                                "call_id": parsedInput.callId.map(JSONValue.string) ?? .null,
                                "status": .string("completed")
                            ]
                            if let arguments = parsedInput.arguments {
                                payload["arguments"] = arguments
                            }
                            items.append(.object(payload))
                            continue
                        }

                        if hasLocalShellTool, resolvedToolName == "local_shell" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiLocalShellInputSchema)
                            )

                            var action: [String: JSONValue] = [
                                "type": .string("exec"),
                                "command": .array(parsed.action.command.map(JSONValue.string))
                            ]
                            if let timeout = parsed.action.timeoutMs {
                                action["timeout_ms"] = .number(Double(timeout))
                            }
                            if let user = parsed.action.user {
                                action["user"] = .string(user)
                            }
                            if let workingDirectory = parsed.action.workingDirectory {
                                action["working_directory"] = .string(workingDirectory)
                            }
                            if let env = parsed.action.env {
                                action["env"] = .object(env.mapValues(JSONValue.string))
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("local_shell_call"),
                                "call_id": .string(callPart.toolCallId),
                                "action": .object(action)
                            ]

                            if let itemId {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        if hasShellTool, resolvedToolName == "shell" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiShellInputSchema)
                            )

                            var action: [String: JSONValue] = [
                                "commands": .array(parsed.action.commands.map(JSONValue.string))
                            ]
                            if let timeout = parsed.action.timeoutMs {
                                action["timeout_ms"] = .number(timeout)
                            }
                            if let maxOutputLength = parsed.action.maxOutputLength {
                                action["max_output_length"] = .number(maxOutputLength)
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("shell_call"),
                                "call_id": .string(callPart.toolCallId),
                                "status": .string("completed"),
                                "action": .object(action)
                            ]

                            if let itemId {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        if hasApplyPatchTool, resolvedToolName == "apply_patch" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiApplyPatchInputSchema)
                            )

                            let operation: JSONValue = switch parsed.operation {
                            case let .createFile(path, diff):
                                .object([
                                    "type": .string("create_file"),
                                    "path": .string(path),
                                    "diff": .string(diff)
                                ])
                            case let .deleteFile(path):
                                .object([
                                    "type": .string("delete_file"),
                                    "path": .string(path)
                                ])
                            case let .updateFile(path, diff):
                                .object([
                                    "type": .string("update_file"),
                                    "path": .string(path),
                                    "diff": .string(diff)
                                ])
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("apply_patch_call"),
                                "call_id": .string(parsed.callId),
                                "status": .string("completed"),
                                "operation": operation
                            ]

                            if let itemId {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        if customProviderToolNames.contains(resolvedToolName) {
                            let input: String
                            if case .string(let value) = callPart.input {
                                input = value
                            } else {
                                input = try encodeJSONStringifiedValue(callPart.input)
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("custom_tool_call"),
                                "call_id": .string(callPart.toolCallId),
                                "name": .string(resolvedToolName),
                                "input": .string(input)
                            ]
                            if let itemId {
                                payload["id"] = .string(itemId)
                            }
                            items.append(.object(payload))
                            continue
                        }

                        let arguments = try encodeJSONValue(callPart.input)
                        var payload: [String: JSONValue] = [
                            "type": .string("function_call"),
                            "call_id": .string(callPart.toolCallId),
                            "name": .string(resolvedToolName),
                            "arguments": .string(arguments)
                        ]
                        if let itemId {
                            payload["id"] = .string(itemId)
                        }
                        items.append(.object(payload))

                    case .toolResult(let resultPart):
                        if case .executionDenied = resultPart.output {
                            continue
                        }

                        if case .json(let value, _) = resultPart.output,
                           case .object(let object) = value,
                           object["type"] == .string("execution-denied") {
                            continue
                        }

                        if hasConversation {
                            continue
                        }

                        let resolvedResultToolName = toolNameMapping.toProviderToolName(resultPart.toolName)

                        if resolvedResultToolName == "tool_search" {
                            let itemId =
                                extractOpenAIItemId(from: resultPart.providerOptions, providerOptionsName: providerOptionsName)
                                ?? extractOpenAIItemId(from: resultPart.providerMetadata, providerOptionsName: providerOptionsName)
                                ?? resultPart.toolCallId

                            if store {
                                items.append(.object([
                                    "type": .string("item_reference"),
                                    "id": .string(itemId)
                                ]))
                            } else if case .json(let value, _) = resultPart.output {
                                let parsedOutput = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiToolSearchOutputSchema)
                                )
                                items.append(.object([
                                    "type": .string("tool_search_output"),
                                    "id": .string(itemId),
                                    "execution": .string("server"),
                                    "call_id": .null,
                                    "status": .string("completed"),
                                    "tools": .array(parsedOutput.tools)
                                ]))
                            }
                            continue
                        }

                        // shell_call_output has a separate item identity in OpenAI store, so
                        // we reconstruct it instead of referencing the shell_call item id.
                        if hasShellTool, resolvedResultToolName == "shell" {
                            if case .json(let value, _) = resultPart.output {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiShellOutputSchema)
                                )

                                let output: JSONValue = .array(parsed.output.map { item in
                                    let outcome: JSONValue = switch item.outcome {
                                    case .timeout:
                                        .object(["type": .string("timeout")])
                                    case .exit(let exitCode):
                                        .object([
                                            "type": .string("exit"),
                                            "exit_code": .number(exitCode)
                                        ])
                                    }

                                    return .object([
                                        "stdout": .string(item.stdout),
                                        "stderr": .string(item.stderr),
                                        "outcome": outcome
                                    ])
                                })

                                items.append(.object([
                                    "type": .string("shell_call_output"),
                                    "call_id": .string(resultPart.toolCallId),
                                    "output": output
                                ]))
                            }
                            continue
                        }

                        if store {
                            let itemId =
                                extractOpenAIItemId(from: resultPart.providerMetadata, providerOptionsName: providerOptionsName)
                                ?? resultPart.toolCallId
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                        } else {
                            warnings.append(.other(message: "Results for OpenAI tool \(resultPart.toolName) are not sent to the API when store is false"))
                        }

                    case .reasoning(let reasoningPart):
                        let providerOptions = try await parseProviderOptions(
                            provider: providerOptionsName,
                            providerOptions: reasoningPart.providerOptions,
                            schema: openAIResponsesReasoningProviderOptionsSchema
                        )

                        if let reasoningId = providerOptions?.itemId {
                            if hasConversation || hasPreviousResponseId {
                                continue
                            }

                            if store {
                                if !reasoningReferences.contains(reasoningId) {
                                    items.append(.object([
                                        "type": .string("item_reference"),
                                        "id": .string(reasoningId)
                                    ]))
                                    reasoningReferences.insert(reasoningId)
                                }
                                continue
                            }

                            var accumulator = reasoningMessages[reasoningId]
                            let isFirstPart = accumulator == nil

                            if accumulator == nil {
                                let newAccumulator = ReasoningAccumulator(
                                    id: reasoningId,
                                    encryptedContent: providerOptions?.reasoningEncryptedContent,
                                    summaryParts: [],
                                    itemIndex: items.count
                                )
                                items.append(newAccumulator.asJSONValue())
                                reasoningMessages[reasoningId] = newAccumulator
                                accumulator = newAccumulator
                            }

                            guard var existing = accumulator else { continue }

                            if let encryptedContent = providerOptions?.reasoningEncryptedContent {
                                existing.encryptedContent = encryptedContent
                            }

                            if !reasoningPart.text.isEmpty {
                                existing.summaryParts.append(.object([
                                    "type": .string("summary_text"),
                                    "text": .string(reasoningPart.text)
                                ]))
                            } else if !isFirstPart {
                                // Only warn when appending empty text to existing sequence
                                let partDescription = stringifyReasoningPart(reasoningPart)
                                warnings.append(.other(message: "Cannot append empty reasoning part to existing reasoning sequence. Skipping reasoning part: \(partDescription)."))
                            }

                            items[existing.itemIndex] = existing.asJSONValue()
                            reasoningMessages[reasoningId] = existing
                            continue
                        }

                        if let encryptedContent = providerOptions?.reasoningEncryptedContent {
                            var summaryParts: [JSONValue] = []
                            if !reasoningPart.text.isEmpty {
                                summaryParts.append(.object([
                                    "type": .string("summary_text"),
                                    "text": .string(reasoningPart.text)
                                ]))
                            }

                            items.append(.object([
                                "type": .string("reasoning"),
                                "encrypted_content": .string(encryptedContent),
                                "summary": .array(summaryParts)
                            ]))
                            continue
                        }

                        let partDescription = stringifyReasoningPart(reasoningPart)
                        warnings.append(.other(message: "Non-OpenAI reasoning parts are not supported. Skipping reasoning part: \(partDescription)."))

                    case .custom(let customPart):
                        guard customPart.kind == "openai.compaction" else { continue }
                        let providerOptions = customPart.providerOptions?[providerOptionsName]
                        let itemId = providerOptions?["itemId"]?.stringValue

                        if hasConversation, itemId != nil {
                            continue
                        }

                        if store, let itemId {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                            continue
                        }

                        if let itemId,
                           let encryptedContent = providerOptions?["encryptedContent"]?.stringValue {
                            items.append(.object([
                                "type": .string("compaction"),
                                "id": .string(itemId),
                                "encrypted_content": .string(encryptedContent)
                            ]))
                        }

                    case .file:
                        continue
                    }
                }

            case let .tool(parts, _):
                for part in parts {
                    switch part {
                    case .toolApprovalResponse(let approvalResponse):
                        if processedApprovalIds.contains(approvalResponse.approvalId) {
                            continue
                        }
                        processedApprovalIds.insert(approvalResponse.approvalId)

                        if store {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(approvalResponse.approvalId)
                            ]))
                        }

                        items.append(.object([
                            "type": .string("mcp_approval_response"),
                            "approval_request_id": .string(approvalResponse.approvalId),
                            "approve": .bool(approvalResponse.approved)
                        ]))

                    case .toolResult(let toolResult):
                        // Skip execution-denied with approvalId - already handled via tool-approval-response
                        if case .executionDenied(_, let providerOptions) = toolResult.output,
                           extractOpenAIStringOption(from: providerOptions, providerOptionsName: "openai", key: "approvalId") != nil {
                            continue
                        }

                        let resolvedToolName = toolNameMapping.toProviderToolName(toolResult.toolName)

                        if resolvedToolName == "tool_search",
                           case .json(let value, _) = toolResult.output {
                            let parsedOutput = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiToolSearchOutputSchema)
                            )
                            items.append(.object([
                                "type": .string("tool_search_output"),
                                "execution": .string("client"),
                                "call_id": .string(toolResult.toolCallId),
                                "status": .string("completed"),
                                "tools": .array(parsedOutput.tools)
                            ]))
                            continue
                        }

                        switch toolResult.output {
                        case .json(let value, _):
                            if hasLocalShellTool, resolvedToolName == "local_shell" {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiLocalShellOutputSchema)
                                )

                                items.append(.object([
                                    "type": .string("local_shell_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(parsed.output)
                                ]))
                                continue
                            }

                            if hasShellTool, resolvedToolName == "shell" {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiShellOutputSchema)
                                )

                                let output: JSONValue = .array(parsed.output.map { item in
                                    let outcome: JSONValue = switch item.outcome {
                                    case .timeout:
                                        .object(["type": .string("timeout")])
                                    case .exit(let exitCode):
                                        .object([
                                            "type": .string("exit"),
                                            "exit_code": .number(exitCode)
                                        ])
                                    }

                                    return .object([
                                        "stdout": .string(item.stdout),
                                        "stderr": .string(item.stderr),
                                        "outcome": outcome
                                    ])
                                })

                                items.append(.object([
                                    "type": .string("shell_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": output
                                ]))
                                continue
                            }

                            if hasApplyPatchTool, resolvedToolName == "apply_patch" {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiApplyPatchOutputSchema)
                                )

                                var payload: [String: JSONValue] = [
                                    "type": .string("apply_patch_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "status": .string(parsed.status)
                                ]
                                if let output = parsed.output {
                                    payload["output"] = .string(output)
                                }

                                items.append(.object(payload))
                                continue
                            }

                            if customProviderToolNames.contains(resolvedToolName) {
                                items.append(.object([
                                    "type": .string("custom_tool_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(try encodeJSONStringifiedValue(value))
                                ]))
                                continue
                            }

                            let jsonString = try encodeJSONValue(value)
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(jsonString)))

                        case .text(let value, _):
                            if customProviderToolNames.contains(resolvedToolName) {
                                items.append(.object([
                                    "type": .string("custom_tool_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(value)
                                ]))
                                continue
                            }
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(value)))

                        case .executionDenied(let reason, _):
                            let message = reason ?? "Tool execution denied."
                            if customProviderToolNames.contains(resolvedToolName) {
                                items.append(.object([
                                    "type": .string("custom_tool_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(message)
                                ]))
                                continue
                            }
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(message)))

                        case .errorText(let value, _):
                            if customProviderToolNames.contains(resolvedToolName) {
                                items.append(.object([
                                    "type": .string("custom_tool_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(value)
                                ]))
                                continue
                            }
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(value)))

                        case .errorJson(let value, _):
                            if customProviderToolNames.contains(resolvedToolName) {
                                items.append(.object([
                                    "type": .string("custom_tool_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(try encodeJSONStringifiedValue(value))
                                ]))
                                continue
                            }
                            let jsonString = try encodeJSONValue(value)
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(jsonString)))

                        case .content(let contentParts, _):
                            if customProviderToolNames.contains(resolvedToolName) {
                                let converted = try contentParts.compactMap { item in
                                    try convertToolResultContentPart(
                                        item,
                                        providerOptionsName: providerOptionsName,
                                        warningPrefix: "unsupported custom tool content part",
                                        warnings: &warnings
                                    )
                                }

                                items.append(.object([
                                    "type": .string("custom_tool_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .array(converted)
                                ]))
                                continue
                            }

                            let converted = try contentParts.compactMap { item in
                                try convertToolResultContentPart(
                                    item,
                                    providerOptionsName: providerOptionsName,
                                    warningPrefix: "unsupported tool content part",
                                    warnings: &warnings
                                )
                            }
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .array(converted)))
                        }
                    }
                }
            }
        }

        return (items, warnings)
    }

    private static func convertToolResultContentPart(
        _ part: OpenAIResponsesToolResultContentPart,
        providerOptionsName: String,
        warningPrefix: String,
        warnings: inout [SharedV3Warning]
    ) throws -> JSONValue? {
        switch part {
        case let .text(text, providerOptions):
            var payload: [String: JSONValue] = [
                "type": .string("input_text"),
                "text": .string(text)
            ]
            addPromptCacheBreakpoint(
                to: &payload,
                providerOptions: providerOptions,
                providerOptionsName: providerOptionsName
            )
            return .object(payload)

        case let .file(data, mediaType, filename, providerOptions):
            let topLevel = getTopLevelMediaType(mediaType)
            let fullMediaType: String
            let inlineBase64: String?
            let url: URL?

            switch data {
            case .data(let value):
                fullMediaType = try resolveToolResultMediaType(mediaType, data: value)
                inlineBase64 = convertDataToBase64(value)
                url = nil
            case .base64(let value):
                fullMediaType = try resolveToolResultMediaType(mediaType, base64: value)
                inlineBase64 = value
                url = nil
            case .url(let value):
                guard isFullMediaType(mediaType) else {
                    warnings.append(.other(message: "\(warningPrefix) type: file with data type: url"))
                    return nil
                }
                fullMediaType = mediaType
                inlineBase64 = nil
                url = value
            case .reference, .text:
                warnings.append(.other(message: "\(warningPrefix) type: file with unsupported data type"))
                return nil
            }

            var payload: [String: JSONValue]
            if topLevel == "image" {
                payload = ["type": .string("input_image")]
                if let url {
                    payload["image_url"] = .string(url.absoluteString)
                } else if let inlineBase64 {
                    payload["image_url"] = .string("data:\(fullMediaType);base64,\(inlineBase64)")
                }
                if let detail = extractOpenAIStringOption(
                    from: providerOptions,
                    providerOptionsName: providerOptionsName,
                    key: "imageDetail"
                ) {
                    payload["detail"] = .string(detail)
                }
            } else {
                payload = ["type": .string("input_file")]
                if let url {
                    payload["file_url"] = .string(url.absoluteString)
                } else if let inlineBase64 {
                    payload["filename"] = .string(filename ?? "data")
                    payload["file_data"] = .string("data:\(fullMediaType);base64,\(inlineBase64)")
                }
            }
            addPromptCacheBreakpoint(
                to: &payload,
                providerOptions: providerOptions,
                providerOptionsName: providerOptionsName
            )
            return .object(payload)

        case .custom:
            warnings.append(.other(message: "\(warningPrefix) type: custom"))
            return nil
        }
    }

    private static func resolveToolResultMediaType(_ mediaType: String, data: Data) throws -> String {
        if isFullMediaType(mediaType) {
            return mediaType
        }
        if let detected = detectMediaType(data: data, topLevelType: getTopLevelMediaType(mediaType)) {
            return detected
        }
        throw UnsupportedFunctionalityError(
            functionality: "file of media type \"\(mediaType)\" must specify subtype since it could not be auto-detected"
        )
    }

    private static func resolveToolResultMediaType(_ mediaType: String, base64: String) throws -> String {
        if isFullMediaType(mediaType) {
            return mediaType
        }
        if let detected = detectMediaType(data: base64, topLevelType: getTopLevelMediaType(mediaType)) {
            return detected
        }
        throw UnsupportedFunctionalityError(
            functionality: "file of media type \"\(mediaType)\" must specify subtype since it could not be auto-detected"
        )
    }

    private static func addPromptCacheBreakpoint(
        to payload: inout [String: JSONValue],
        providerOptions: SharedV3ProviderOptions?,
        providerOptionsName: String
    ) {
        if let breakpoint = openAIPromptCacheBreakpoint(
            from: providerOptions,
            providerOptionsName: providerOptionsName
        ) {
            payload["prompt_cache_breakpoint"] = breakpoint
        }
    }

    private static func systemItem(
        role: String,
        content: String,
        providerOptions: SharedV3ProviderOptions?,
        providerOptionsName: String
    ) -> JSONValue {
        let contentValue: JSONValue
        if let breakpoint = openAIPromptCacheBreakpoint(
            from: providerOptions,
            providerOptionsName: providerOptionsName
        ) {
            contentValue = .array([.object([
                "type": .string("input_text"),
                "text": .string(content),
                "prompt_cache_breakpoint": breakpoint
            ])])
        } else {
            contentValue = .string(content)
        }
        return .object([
            "role": .string(role),
            "content": contentValue
        ])
    }

    private static func convertUserPart(
        _ part: LanguageModelV3UserMessagePart,
        index: Int,
        prefixes: [String]?,
        providerOptionsName: String,
        passThroughUnsupportedFiles: Bool
    ) throws -> JSONValue {
        switch part {
        case .text(let textPart):
            var payload: [String: JSONValue] = [
                "type": .string("input_text"),
                "text": .string(textPart.text)
            ]
            addPromptCacheBreakpoint(
                to: &payload,
                providerOptions: textPart.providerOptions,
                providerOptionsName: providerOptionsName
            )
            return .object(payload)
        case .file(let filePart):
            let converted = try convertFilePart(
                part: filePart,
                index: index,
                prefixes: prefixes,
                providerOptionsName: providerOptionsName,
                passThroughUnsupportedFiles: passThroughUnsupportedFiles
            )
            guard case .object(var payload) = converted else {
                return converted
            }
            addPromptCacheBreakpoint(
                to: &payload,
                providerOptions: filePart.providerOptions,
                providerOptionsName: providerOptionsName
            )
            return .object(payload)
        }
    }

    private static func convertFilePart(
        part: LanguageModelV3FilePart,
        index: Int,
        prefixes: [String]?,
        providerOptionsName: String,
        passThroughUnsupportedFiles: Bool
    ) throws -> JSONValue {
        if part.mediaType.hasPrefix("image/") {
            let mediaType = part.mediaType == "image/*" ? "image/jpeg" : part.mediaType
            let detail = extractOpenAIStringOption(
                from: part.providerOptions,
                providerOptionsName: providerOptionsName,
                key: "imageDetail"
            )
            switch part.data {
            case .url(let url):
                var payload: [String: JSONValue] = [
                    "type": .string("input_image"),
                    "image_url": .string(url.absoluteString)
                ]
                if let detail {
                    payload["detail"] = .string(detail)
                }
                return .object(payload)
            case .base64(let value):
                if isFileId(value, prefixes: prefixes) {
                    var payload: [String: JSONValue] = [
                        "type": .string("input_image"),
                        "file_id": .string(value)
                    ]
                    if let detail {
                        payload["detail"] = .string(detail)
                    }
                    return .object(payload)
                }
                var payload: [String: JSONValue] = [
                    "type": .string("input_image"),
                    "image_url": .string("data:\(mediaType);base64,\(value)")
                ]
                if let detail {
                    payload["detail"] = .string(detail)
                }
                return .object(payload)
            case .data(let data):
                let base64 = convertDataToBase64(data)
                var payload: [String: JSONValue] = [
                    "type": .string("input_image"),
                    "image_url": .string("data:\(mediaType);base64,\(base64)")
                ]
                if let detail {
                    payload["detail"] = .string(detail)
                }
                return .object(payload)
            }
        }

        if part.mediaType == "application/pdf" {
            switch part.data {
            case .url(let url):
                return .object([
                    "type": .string("input_file"),
                    "file_url": .string(url.absoluteString)
                ])
            case .base64(let value):
                if isFileId(value, prefixes: prefixes) {
                    return .object([
                        "type": .string("input_file"),
                        "file_id": .string(value)
                    ])
                }
                return .object([
                    "type": .string("input_file"),
                    "filename": .string(part.filename ?? "part-\(index).pdf"),
                    "file_data": .string("data:application/pdf;base64,\(value)")
                ])
            case .data(let data):
                let base64 = convertDataToBase64(data)
                return .object([
                    "type": .string("input_file"),
                    "filename": .string(part.filename ?? "part-\(index).pdf"),
                    "file_data": .string("data:application/pdf;base64,\(base64)")
                ])
            }
        }

        switch part.data {
        case .url(let url):
            return .object([
                "type": .string("input_file"),
                "file_url": .string(url.absoluteString)
            ])
        case .base64(let value):
            guard passThroughUnsupportedFiles else {
                throw UnsupportedFunctionalityError(functionality: "file media type \(part.mediaType)")
            }
            if isFileId(value, prefixes: prefixes) {
                return .object([
                    "type": .string("input_file"),
                    "file_id": .string(value)
                ])
            }
            return .object([
                "type": .string("input_file"),
                "filename": .string(part.filename ?? "part-\(index)"),
                "file_data": .string("data:\(part.mediaType);base64,\(value)")
            ])
        case .data(let data):
            guard passThroughUnsupportedFiles else {
                throw UnsupportedFunctionalityError(functionality: "file media type \(part.mediaType)")
            }
            let base64 = convertDataToBase64(data)
            return .object([
                "type": .string("input_file"),
                "filename": .string(part.filename ?? "part-\(index)"),
                "file_data": .string("data:\(part.mediaType);base64,\(base64)")
            ])
        }
    }

    private static func isFileId(_ value: String, prefixes: [String]?) -> Bool {
        guard let prefixes else { return false }
        return prefixes.contains { value.hasPrefix($0) }
    }

    private static func encodeJSONValue(_ value: JSONValue) throws -> String {
        func toAny(_ value: JSONValue) -> Any {
            switch value {
            case .null: return NSNull()
            case .bool(let bool): return bool
            case .number(let number): return number
            case .string(let string): return string
            case .array(let array): return array.map { toAny($0) }
            case .object(let object): return object.mapValues { toAny($0) }
            }
        }

        // JSONSerialization requires top-level object to be Array or Dictionary
        // For primitive values, we need to handle them specially
        let anyValue = toAny(value)
        let data: Data

        if anyValue is [Any] || anyValue is [String: Any] {
            data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
        } else {
            // For primitives (number, string, bool, null), encode them directly
            switch value {
            case .null:
                return "null"
            case .bool(let bool):
                return bool ? "true" : "false"
            case .number(let number):
                // Handle integer vs decimal
                if number.truncatingRemainder(dividingBy: 1) == 0 {
                    return String(format: "%.0f", number)
                } else {
                    return String(number)
                }
            case .string(let string):
                // Need to properly escape the string as JSON
                data = try JSONSerialization.data(withJSONObject: [string], options: [])
                guard let arrayString = String(data: data, encoding: .utf8),
                      arrayString.hasPrefix("[\""),
                      arrayString.hasSuffix("\"]") else {
                    throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON string")
                }
                return String(arrayString.dropFirst(2).dropLast(2))
            case .array, .object:
                // Should not reach here due to earlier check
                data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
            }
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }

    private static func encodeJSONStringifiedValue(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }

    private static func makeToolResultObject(toolCallId: String, output: JSONValue) -> JSONValue {
        .object([
            "type": .string("function_call_output"),
            "call_id": .string(toolCallId),
            "output": output
        ])
    }



    private static func extractOpenAIStringOption(
        from options: ProviderOptions?,
        providerOptionsName: String,
        key: String
    ) -> String? {
        guard let options,
              let openaiOptions = options[providerOptionsName],
              let value = openaiOptions[key],
              case .string(let stringValue) = value else {
            return nil
        }
        return stringValue
    }

    private static func stringifyReasoningPart(_ part: LanguageModelV3ReasoningPart) -> String {
        let encoder = JSONEncoder()
        var segments: [String] = []

        if let typeData = try? encoder.encode("reasoning"),
           let typeJSON = String(data: typeData, encoding: .utf8) {
            segments.append("\"type\":\(typeJSON)")
        }

        if let textData = try? encoder.encode(part.text),
           let textJSON = String(data: textData, encoding: .utf8) {
            segments.append("\"text\":\(textJSON)")
        }

        if let providerOptions = part.providerOptions,
           let providerData = try? encoder.encode(providerOptions),
           let providerJSON = String(data: providerData, encoding: .utf8) {
            segments.append("\"providerOptions\":\(providerJSON)")
        }

        if segments.isEmpty {
            return part.text
        }

        return "{\(segments.joined(separator: ","))}"
    }

    private static func extractOpenAIItemId(from options: ProviderOptions?, providerOptionsName: String) -> String? {
        extractOpenAIStringOption(from: options, providerOptionsName: providerOptionsName, key: "itemId")
    }
}

private struct ReasoningAccumulator: Sendable {
    let id: String
    var encryptedContent: String?
    var summaryParts: [JSONValue]
    let itemIndex: Int

    func asJSONValue() -> JSONValue {
        var payload: [String: JSONValue] = [
            "type": .string("reasoning"),
            "id": .string(id),
            "summary": .array(summaryParts)
        ]
        if let encryptedContent {
            payload["encrypted_content"] = .string(encryptedContent)
        }
        return .object(payload)
    }
}

private struct OpenAIResponsesReasoningProviderOptions: Sendable, Equatable {
    let itemId: String?
    let reasoningEncryptedContent: String?
}

private let openAIResponsesReasoningProviderOptionsSchema = FlexibleSchema<OpenAIResponsesReasoningProviderOptions>(
    Schema(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true),
                "properties": .object([
                    "itemId": .object(["type": .array([.string("string"), .string("null")])]),
                    "reasoningEncryptedContent": .object(["type": .array([.string("string"), .string("null")])])
                ])
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let itemId = try parseOptionalString(dict, key: "itemId")
                let encrypted = try parseOptionalString(dict, key: "reasoningEncryptedContent")
                return .success(value: OpenAIResponsesReasoningProviderOptions(itemId: itemId, reasoningEncryptedContent: encrypted))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let stringValue) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return stringValue
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
