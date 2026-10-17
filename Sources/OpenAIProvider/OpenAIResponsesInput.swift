import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesInputBuilder {
    static func makeInput(
        prompt: LanguageModelV4Prompt,
        providerOptionsName: String = "openai",
        toolNameMapping: ToolNameMapping = .init(),
        customProviderToolNames: Set<Data> = [],
        outputSchemaToolNames: Set<Data> = [],
        systemMessageMode: OpenAIResponsesSystemMessageMode = .system,
        fileIdPrefixes: [String]? = ["file-"],
        store: Bool = true,
        hasConversation: Bool = false,
        hasPreviousResponseId: Bool = false,
        passThroughUnsupportedFiles: Bool = false,
        hasLocalShellTool: Bool = false,
        hasShellTool: Bool = false,
        hasApplyPatchTool: Bool = false,
        hasComputerTool: Bool = false,
        explicitMessageItemType: Bool = false,
        isReasoningModel: Bool = false,
        toolSearchToolName: String? = nil
    ) async throws -> (input: OpenAIResponsesInput, warnings: [SharedV4Warning]) {
        var items: [JSONValue] = []
        var warnings: [SharedV4Warning] = []
        var processedApprovalIds: Set<Data> = []
        var programmaticToolCallIds: Set<Data> = []
        let parallelGroups = hasConversation || hasPreviousResponseId ? OpenAIParallelCalls.completeGroups(prompt, namespace: providerOptionsName) : [:]
        var emittedParallelCalls: Set<Data> = []
        var emittedParallelResults: Set<Data> = []

        for message in prompt {
            switch message {
            case let .system(content, providerOptions):
                switch systemMessageMode {
                case .system:
                    items.append(systemItem(
                        role: "system",
                        content: content,
                        providerOptions: providerOptions,
                        providerOptionsName: providerOptionsName,
                        explicitMessageItemType: explicitMessageItemType
                    ))
                case .developer:
                    items.append(systemItem(
                        role: "developer",
                        content: content,
                        providerOptions: providerOptions,
                        providerOptionsName: providerOptionsName,
                        explicitMessageItemType: explicitMessageItemType
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

                items.append(.object(Self.message(role: "user", content: .array(content), explicit: explicitMessageItemType)))

            case let .assistant(parts, _):
                var reasoningMessages: [Data: ReasoningAccumulator] = [:]
                var emittedTextIds: Set<Data> = []
                var hasPrecedingReasoning = false

                for part in parts {
                    switch part {
                    case .text(let textPart):
                        let itemId = extractOpenAIStringOption(
                            from: textPart.providerOptions,
                            providerOptionsName: providerOptionsName,
                            key: "itemId"
                        )
                        let phase = textPart.providerOptions?[providerOptionsName]?["phase"]

                        if hasConversation, itemId != nil {
                            continue
                        }

                        if store, let itemId, !isReasoningModel || hasPrecedingReasoning {
                            if emittedTextIds.insert(Data(itemId.utf8)).inserted {
                                items.append(.object(["type": .string("item_reference"), "id": .string(itemId)]))
                            }
                            continue
                        }

                        var payload = Self.message(role: "assistant", content: .string(textPart.text), explicit: explicitMessageItemType)
                        if let phase, phase != .null { payload["phase"] = phase }

                        items.append(.object(payload))

                    case .toolCall(let callPart):
                        if let metadata = OpenAIParallelCalls.metadata(callPart.providerOptions, namespace: providerOptionsName),
                           let group = parallelGroups[metadata.key], group.metadata.matches(metadata) {
                            if emittedParallelCalls.insert(metadata.key).inserted, !hasConversation {
                                items.append(.object(["type": .string("function_call"), "call_id": .string(metadata.toolCallId), "name": .string(metadata.toolName), "arguments": .string(metadata.input)]))
                            }
                            continue
                        }
                        let itemId =
                            extractOpenAIItemId(from: callPart.providerOptions, providerOptionsName: providerOptionsName)
                        let caller = callPart.providerOptions?[providerOptionsName]?["caller"]
                        if case .object(let caller)? = caller, caller["type"] == .string("program") {
                            programmaticToolCallIds.insert(Data(callPart.toolCallId.utf8))
                        }

                        if hasConversation, itemId != nil {
                            continue
                        }

                        let resolvedToolName = toolNameMapping.toProviderToolName(callPart.toolName)
                        if callPart.toolName == toolSearchToolName {
                            if store, let itemId {
                                items.append(.object([
                                    "type": .string("item_reference"),
                                    "id": .string(itemId)
                                ]))
                                continue
                            }

                            let parsedInput: OpenAIToolSearchInput
                            if case .string(let text) = callPart.input {
                                parsedInput = try await parseJSON(ParseJSONWithSchemaOptions(text: text, schema: openaiToolSearchInputSchema))
                            } else {
                                parsedInput = try await validateTypes(ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiToolSearchInputSchema))
                            }
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

                        if resolvedToolName == "programmatic_tool_calling" {
                            if store, let itemId {
                                items.append(.object(["type": .string("item_reference"), "id": .string(itemId)]))
                            } else {
                                let input = try await validateTypes(ValidateTypesOptions(value: callPart.input, schema: openaiProgrammaticToolCallingInputSchema))
                                items.append(.object([
                                    "type": .string("program"), "id": .string(itemId ?? callPart.toolCallId), "call_id": .string(callPart.toolCallId),
                                    "code": .string(input.code), "fingerprint": .string(input.fingerprint)
                                ]))
                            }
                            continue
                        }

                        if callPart.providerExecuted == true {
                            if store, let itemId { items.append(.object(["type": .string("item_reference"), "id": .string(itemId)])) }
                            if store || !hasShellTool || resolvedToolName != "shell" { continue }
                        }
                        let isProviderDefined = (hasLocalShellTool && resolvedToolName == "local_shell")
                            || (hasShellTool && resolvedToolName == "shell") || (hasApplyPatchTool && resolvedToolName == "apply_patch")
                            || (hasComputerTool && resolvedToolName == "computer")
                            || customProviderToolNames.contains(Data(resolvedToolName.utf8))
                        if hasPreviousResponseId && store && itemId != nil && isProviderDefined { continue }
                        if store, let itemId, isProviderDefined {
                            items.append(.object(["type": .string("item_reference"), "id": .string(itemId)]))
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

                        if hasComputerTool, resolvedToolName == "computer" {
                            let input = try await validateTypes(ValidateTypesOptions(value: callPart.input, schema: openaiComputerInputSchema))
                            items.append(input.wireCall(id: itemId, callId: callPart.toolCallId))
                            continue
                        }

                        if customProviderToolNames.contains(Data(resolvedToolName.utf8)) {
                            let input: String
                            if case .string(let value) = callPart.input {
                                input = value
                            } else {
                                input = try openAIJSONStringify(callPart.input)
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("custom_tool_call"),
                                "call_id": .string(callPart.toolCallId),
                                "name": .string(resolvedToolName),
                                "input": .string(input)
                            ]
                            if let itemId { payload["id"] = .string(itemId) }
                            if let value = callPart.providerOptions?[providerOptionsName]?["async"], value != .null { payload["async"] = value }
                            items.append(.object(payload))
                            continue
                        }

                        let arguments = try openAIJSONStringify(callPart.input)
                        var payload: [String: JSONValue] = [
                            "type": .string("function_call"),
                            "call_id": .string(callPart.toolCallId),
                            "name": .string(resolvedToolName),
                            "arguments": .string(arguments)
                        ]
                        for key in ["async", "namespace"] {
                            if let value = callPart.providerOptions?[providerOptionsName]?[key], value != .null { payload[key] = value }
                        }
                        payload["caller"] = wireCaller(caller)
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
                        if resolvedResultToolName == "web_search" || resolvedResultToolName == "web_search_preview" {
                            let itemId = extractOpenAIItemId(from: resultPart.providerOptions, providerOptionsName: providerOptionsName) ?? resultPart.toolCallId
                            if store {
                                items.append(.object(["type": .string("item_reference"), "id": .string(itemId)]))
                                continue
                            }
                            if let call = await webSearchReplay(resultPart.output, id: itemId) {
                                items.append(call)
                                continue
                            }
                        }

                        if resultPart.toolName == toolSearchToolName {
                            let itemId =
                                extractOpenAIItemId(from: resultPart.providerOptions, providerOptionsName: providerOptionsName)
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

                        if resolvedResultToolName == "programmatic_tool_calling" {
                            let itemId = extractOpenAIItemId(from: resultPart.providerOptions, providerOptionsName: providerOptionsName) ?? resultPart.toolCallId
                            if store {
                                items.append(.object(["type": .string("item_reference"), "id": .string(itemId)]))
                            } else if case .json(let value, _) = resultPart.output {
                                let output = try await validateTypes(ValidateTypesOptions(value: value, schema: openaiProgrammaticToolCallingOutputSchema))
                                items.append(.object([
                                    "type": .string("program_output"), "id": .string(itemId), "call_id": .string(resultPart.toolCallId),
                                    "result": .string(output.result), "status": .string(output.status.rawValue)
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
                                extractOpenAIItemId(from: resultPart.providerOptions, providerOptionsName: providerOptionsName)
                                ?? resultPart.toolCallId
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                        } else {
                            warnings.append(.other(message: "Results for OpenAI tool \(resultPart.toolName) are not sent to the API when store is false"))
                        }

                    case .reasoning(let reasoningPart):
                        hasPrecedingReasoning = true
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
                                if reasoningMessages[Data(reasoningId.utf8)] == nil {
                                    items.append(.object([
                                        "type": .string("item_reference"),
                                        "id": .string(reasoningId)
                                    ]))
                                    reasoningMessages[Data(reasoningId.utf8)] = ReasoningAccumulator(id: reasoningId, encryptedContent: nil, summaryParts: [], itemIndex: items.count - 1)
                                }
                                continue
                            }

                            var accumulator = reasoningMessages[Data(reasoningId.utf8)]
                            let isFirstPart = accumulator == nil

                            if accumulator == nil {
                                let newAccumulator = ReasoningAccumulator(
                                    id: reasoningId,
                                    encryptedContent: providerOptions?.reasoningEncryptedContent,
                                    summaryParts: [],
                                    itemIndex: items.count
                                )
                                items.append(newAccumulator.asJSONValue())
                                reasoningMessages[Data(reasoningId.utf8)] = newAccumulator
                                accumulator = newAccumulator
                            }

                            guard let existing = accumulator else { continue }

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

                    case .file, .reasoningFile:
                        continue
                    }
                }
                if !store {
                    for accumulator in reasoningMessages.values { items[accumulator.itemIndex] = accumulator.asJSONValue() }
                }

            case let .tool(parts, _):
                for part in parts {
                    switch part {
                    case .toolApprovalResponse(let approvalResponse):
                        if processedApprovalIds.contains(Data(approvalResponse.approvalId.utf8)) {
                            continue
                        }
                        processedApprovalIds.insert(Data(approvalResponse.approvalId.utf8))

                        if store && !hasConversation && !hasPreviousResponseId {
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
                        if let metadata = OpenAIParallelCalls.metadata(toolResult.providerOptions, namespace: providerOptionsName),
                           let group = parallelGroups[metadata.key], group.metadata.matches(metadata) {
                            if emittedParallelResults.insert(metadata.key).inserted {
                                var outputs: [(String, JSONValue?)] = []
                                for result in group.results {
                                    let value = try convertOutput(result.output, custom: false, hasOutputSchema: outputSchemaToolNames.contains(Data(result.toolName.utf8)), breakpoint: nil, namespace: providerOptionsName, warnings: &warnings)
                                    let text: String
                                    if case .string(let scalar) = value { text = scalar } else { text = try openAIJSONStringify(value) }
                                    outputs.append((text, scalarBreakpoint(result.output, options: result.providerOptions, namespace: providerOptionsName)))
                                }
                                let output: JSONValue
                                if outputs.contains(where: { $0.1 != nil }) {
                                    output = .array(outputs.enumerated().map { index, entry in
                                        var text: [String: JSONValue] = ["type": .string("input_text"), "text": .string((index == 0 ? "" : "\n") + entry.0)]
                                        text["prompt_cache_breakpoint"] = entry.1
                                        return .object(text)
                                    })
                                } else { output = .string(outputs.map(\.0).joined(separator: "\n")) }
                                items.append(makeToolResultObject(toolCallId: metadata.toolCallId, output: output))
                            }
                            continue
                        }
                        // Skip execution-denied with approvalId - already handled via tool-approval-response
                        if case .executionDenied(_, let providerOptions) = toolResult.output,
                           let approvalId = extractOpenAIStringOption(from: providerOptions, providerOptionsName: "openai", key: "approvalId"), !approvalId.isEmpty {
                            continue
                        }

                        let resolvedToolName = toolNameMapping.toProviderToolName(toolResult.toolName)

                        if toolResult.toolName == toolSearchToolName,
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

                        if case .json(let value, _) = toolResult.output {
                            if hasComputerTool, resolvedToolName == "computer" {
                                let parsed = try await validateTypes(ValidateTypesOptions(value: value, schema: openaiComputerOutputSchema))
                                items.append(computerOutputPayload(parsed, callId: toolResult.toolCallId))
                                continue
                            }
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

                            if hasApplyPatchTool, toolResult.toolName == "apply_patch" {
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


                        }
                        let custom = customProviderToolNames.contains(Data(resolvedToolName.utf8))
                        let resultCaller = toolResult.providerOptions?[providerOptionsName]?["caller"]
                        if !custom, case .executionDenied = toolResult.output {
                            let fromProgram: Bool
                            if case .object(let caller)? = resultCaller { fromProgram = caller["type"] == .string("program") }
                            else { fromProgram = false }
                            if fromProgram || programmaticToolCallIds.contains(Data(toolResult.toolCallId.utf8)) {
                                throw UnsupportedFunctionalityError(functionality: "execution-denied results for programmatic tool calls")
                            }
                        }
                        let output = try convertOutput(
                            toolResult.output, custom: custom, hasOutputSchema: !custom && outputSchemaToolNames.contains(Data(toolResult.toolName.utf8)),
                            breakpoint: scalarBreakpoint(toolResult.output, options: toolResult.providerOptions, namespace: providerOptionsName),
                            namespace: providerOptionsName, warnings: &warnings
                        )
                        var payload: [String: JSONValue] = [
                            "type": .string(custom ? "custom_tool_call_output" : "function_call_output"),
                            "call_id": .string(toolResult.toolCallId), "output": output
                        ]
                        if !custom { payload["caller"] = wireCaller(resultCaller) }
                        items.append(.object(payload))
                    }
                }
            }
        }

        if !store {
            let unsupported: (JSONValue) -> Bool = { value in
                guard case .object(let item) = value, item["type"] == .string("reasoning") else { return false }
                return item["encrypted_content"] == nil || item["encrypted_content"] == .null
            }
            if items.contains(where: unsupported) {
                warnings.append(.other(message: "Reasoning parts without encrypted content are not supported when store is false. Skipping reasoning parts."))
                items.removeAll(where: unsupported)
            }
        }
        return (items, warnings)
    }

    private static func wireCaller(_ value: JSONValue?) -> JSONValue? {
        guard let value, value != .null else { return nil }
        if case .object(let caller) = value, caller["type"] == .string("program") {
            var result: [String: JSONValue] = ["type": .string("program")]
            result["caller_id"] = caller["callerId"]
            return .object(result)
        }
        return value
    }

    private static func webSearchReplay(_ output: LanguageModelV4ToolResultOutput, id: String) async -> JSONValue? {
        guard case .json(let value, _) = output,
              case .success(let validated, _) = await safeValidateTypes(ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiWebSearchOutputSchema)),
              case .object(let result) = validated, case .object(let action)? = result["action"],
              case .string(let type)? = action["type"] else { return nil }
        var wire: [String: JSONValue]
        switch type {
        case "search":
            wire = ["type": .string("search")]
            for key in ["query", "queries"] { if let value = action[key], value != .null { wire[key] = value } }
            if let sources = result["sources"], sources != .null { wire["sources"] = sources }
        case "openPage":
            wire = ["type": .string("open_page")]
            wire["url"] = action["url"]
        case "findInPage":
            wire = ["type": .string("find_in_page")]
            wire["url"] = action["url"]
            wire["pattern"] = action["pattern"]
        default: return nil
        }
        return .object(["type": .string("web_search_call"), "id": .string(id), "status": .string("completed"), "action": .object(wire)])
    }

    private static func message(role: String, content: JSONValue, explicit: Bool) -> [String: JSONValue] {
        var value: [String: JSONValue] = ["role": .string(role), "content": content]
        if explicit { value["type"] = .string("message") }
        return value
    }

    private static func scalarBreakpoint(_ output: LanguageModelV4ToolResultOutput, options: SharedV4ProviderOptions?, namespace: String) -> JSONValue? {
        let outputOptions: SharedV4ProviderOptions?
        switch output {
        case .content: return nil
        case .text(_, let value), .json(_, let value), .executionDenied(_, let value), .errorText(_, let value), .errorJson(_, let value): outputOptions = value
        }
        return openAIPromptCacheBreakpoint(from: outputOptions, providerOptionsName: namespace)
            ?? openAIPromptCacheBreakpoint(from: options, providerOptionsName: namespace)
    }

    private static func convertOutput(_ output: LanguageModelV4ToolResultOutput, custom: Bool, hasOutputSchema: Bool, breakpoint: JSONValue?, namespace: String, warnings: inout [SharedV4Warning]) throws -> JSONValue {
        let text: String
        switch output {
        case .text(let value, _): text = hasOutputSchema ? try openAIJSONStringify(.string(value)) : value
        case .json(let value, _): text = try openAIJSONStringify(value)
        case .errorText(let value, _): text = try openAIJSONStringify(.object(["error": .string(value)]))
        case .errorJson(let value, _): text = try openAIJSONStringify(.object(["error": value]))
        case .executionDenied(let reason, _):
            let reason = reason ?? "Tool call execution denied."
            text = hasOutputSchema ? try openAIJSONStringify(.string(reason)) : reason
        case .content(let parts):
            return .array(try parts.compactMap {
                try convertToolResultContentPart($0, providerOptionsName: namespace, warningPrefix: custom ? "unsupported custom tool content part" : "unsupported tool content part", allowReferences: !custom, warnings: &warnings)
            })
        }
        guard let breakpoint else { return .string(text) }
        return .array([.object(["type": .string("input_text"), "text": .string(text), "prompt_cache_breakpoint": breakpoint])])
    }

    private static func convertToolResultContentPart(
        _ part: LanguageModelV4ToolResultContentPart,
        providerOptionsName: String,
        warningPrefix: String,
        allowReferences: Bool,
        warnings: inout [SharedV4Warning]
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
            let image = getTopLevelMediaType(mediaType) == "image"
            var payload: [String: JSONValue] = ["type": .string(image ? "input_image" : "input_file")]
            switch data {
            case .reference(let reference) where allowReferences:
                payload["file_id"] = .string(try resolveProviderReference(reference: reference, provider: providerOptionsName))
            case .url(let url, _):
                payload[image ? "image_url" : "file_url"] = .string(url.absoluteString)
            case .data, .base64:
                let full = try resolveFullMediaType(part: .init(data: data, mediaType: mediaType))
                let base64: String
                if case .data(let bytes) = data { base64 = convertDataToBase64(bytes) }
                else if case .base64(let value) = data { base64 = value }
                else { preconditionFailure() }
                payload[image ? "image_url" : "file_data"] = .string("data:\(full);base64,\(base64)")
                if !image { payload["filename"] = .string(filename ?? "data") }
            case .reference, .text:
                warnings.append(.other(message: "\(warningPrefix) type: file with unsupported data type"))
                return nil
            }
            if image { payload["detail"] = providerOptions?[providerOptionsName]?["imageDetail"] }
            addPromptCacheBreakpoint(to: &payload, providerOptions: providerOptions, providerOptionsName: providerOptionsName)
            return .object(payload)

        case .custom:
            warnings.append(.other(message: "\(warningPrefix) type: custom"))
            return nil
        }
    }

    private static func addPromptCacheBreakpoint(
        to payload: inout [String: JSONValue],
        providerOptions: SharedV4ProviderOptions?,
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
        providerOptions: SharedV4ProviderOptions?,
        providerOptionsName: String,
        explicitMessageItemType: Bool
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
        return .object(Self.message(role: role, content: contentValue, explicit: explicitMessageItemType))
    }

    private static func convertUserPart(
        _ part: LanguageModelV4UserMessagePart,
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
        part: LanguageModelV4FilePart, index: Int, prefixes: [String]?,
        providerOptionsName: String, passThroughUnsupportedFiles: Bool
    ) throws -> JSONValue {
        let image = getTopLevelMediaType(part.mediaType) == "image"
        var value: [String: JSONValue] = ["type": .string(image ? "input_image" : "input_file")]
        switch part.data {
        case .reference(let reference):
            value["file_id"] = .string(try resolveProviderReference(reference: reference, provider: providerOptionsName))
        case .url(let url, _): value[image ? "image_url" : "file_url"] = .string(url.absoluteString)
        case .text: throw UnsupportedFunctionalityError(functionality: "text file parts")
        case .data, .base64:
            if image, case .base64(let id) = part.data, isFileId(id, prefixes: prefixes) {
                value["file_id"] = .string(id)
            } else {
                let full = try resolveFullMediaType(part: part)
                guard image || full == "application/pdf" || passThroughUnsupportedFiles else {
                    throw UnsupportedFunctionalityError(functionality: "file part media type \(full)")
                }
                if case .base64(let id) = part.data, isFileId(id, prefixes: prefixes) {
                    value["file_id"] = .string(id)
                } else {
                    let base64: String
                    if case .data(let bytes) = part.data { base64 = convertDataToBase64(bytes) }
                    else if case .base64(let text) = part.data { base64 = text }
                    else { preconditionFailure() }
                    value[image ? "image_url" : "file_data"] = .string("data:\(full);base64,\(base64)")
                    if !image { value["filename"] = .string(part.filename ?? "part-\(index)\(full == "application/pdf" ? ".pdf" : "")") }
                }
            }
        }
        if image { value["detail"] = part.providerOptions?[providerOptionsName]?["imageDetail"] }
        return .object(value)
    }

    private static func isFileId(_ value: String, prefixes: [String]?) -> Bool {
        guard let prefixes else { return false }
        return prefixes.contains { value.utf8.starts(with: $0.utf8) }
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

    private static func stringifyReasoningPart(_ part: LanguageModelV4ReasoningPart) -> String {
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

private final class ReasoningAccumulator {
    let id: String
    var encryptedContent: String?
    var summaryParts: [JSONValue]
    let itemIndex: Int
    init(id: String, encryptedContent: String?, summaryParts: [JSONValue], itemIndex: Int) {
        self.id = id
        self.encryptedContent = encryptedContent
        self.summaryParts = summaryParts
        self.itemIndex = itemIndex
    }

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
