import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Parses a tool call from the model response, repairing and refining it when configured.

 Port of `@ai-sdk/ai/src/generate-text/parse-tool-call.ts`. Parse failures that
 cannot be repaired produce an invalid dynamic tool call carrying the error. An
 abort during or after repair is thrown (`CancellationError`) instead.
 */
public func parseToolCall(
    toolCall: LanguageModelV4ToolCall,
    tools: ToolSet?,
    repairToolCall: ToolCallRepairFunction?,
    refineToolInput: ToolInputRefinement? = nil,
    instructions: Instructions?,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)? = nil
) async throws -> TypedToolCall {
    do {
        guard let tools else {
            if toolCall.providerExecuted == true, toolCall.dynamic == true {
                return try await refineParsedToolCallInput(
                    try await parseProviderExecutedDynamicToolCall(toolCall),
                    refineToolInput: refineToolInput
                )
            }
            throw NoSuchToolError(toolName: toolCall.toolName)
        }

        do {
            return try await refineParsedToolCallInput(
                try await doParseToolCall(toolCall: toolCall, tools: tools),
                refineToolInput: refineToolInput
            )
        } catch {
            guard let repairToolCall,
                  NoSuchToolError.isInstance(error) || InvalidToolInputError.isInstance(error) else {
                throw error
            }

            let repairedToolCall: LanguageModelV4ToolCall?
            do {
                try checkAbort(abortSignal)
                let options = ToolCallRepairOptions(
                    instructions: instructions,
                    messages: messages,
                    toolCall: toolCall,
                    tools: tools,
                    inputSchema: { toolName in
                        guard let tool = tools[toolName] else {
                            throw NoSuchToolError(toolName: toolName)
                        }
                        return try await asSchema(tool.inputSchema).jsonSchema()
                    },
                    error: error,
                    abortSignal: abortSignal
                )
                if let abortSignal {
                    // An abort ends the wait even when the repair function ignores it.
                    guard let repaired = try await raceAbort(
                        { try await repairToolCall(options) },
                        abort: { await waitForAbortSignal(abortSignal) }
                    ) else {
                        throw CancellationError()
                    }
                    repairedToolCall = repaired
                } else {
                    repairedToolCall = try await repairToolCall(options)
                }
            } catch let repairError {
                try checkAbort(abortSignal)
                let originalError: ToolCallOriginalError
                if let noSuchTool = error as? NoSuchToolError {
                    originalError = .noSuchTool(noSuchTool)
                } else {
                    originalError = .invalidToolInput(error as! InvalidToolInputError)
                }
                throw ToolCallRepairError(originalError: originalError, cause: repairError)
            }

            guard let repairedToolCall else {
                throw error
            }

            let parsed = try await refineParsedToolCallInput(
                try await doParseToolCall(toolCall: repairedToolCall, tools: tools),
                refineToolInput: refineToolInput
            )
            try checkAbort(abortSignal)
            return parsed
        }
    } catch {
        try checkAbort(abortSignal)

        let parsedInput = await safeParseJSON(ParseJSONOptions(text: toolCall.input))
        let input: JSONValue
        switch parsedInput {
        case .success(let value, _):
            input = value
        case .failure:
            input = .string(toolCall.input)
        }

        let tool = tools?[toolCall.toolName]
        return .dynamic(DynamicToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            title: tool?.title,
            input: input,
            providerExecuted: toolCall.providerExecuted,
            providerMetadata: toolCall.providerMetadata,
            toolMetadata: tool?.metadata,
            invalid: true,
            error: error
        ))
    }
}

/// Throws `CancellationError` when the abort signal fired or the task was cancelled.
func checkAbort(_ abortSignal: (@Sendable () -> Bool)?) throws {
    if abortSignal?() == true {
        throw CancellationError()
    }
}

/**
 Applies the configured input refinement to a parsed tool call.

 Port of `refineParsedToolCallInput` from `@ai-sdk/ai/src/generate-text/parse-tool-call.ts`.
 */
func refineParsedToolCallInput(
    _ toolCall: TypedToolCall,
    refineToolInput: ToolInputRefinement?
) async throws -> TypedToolCall {
    guard let refine = refineToolInput?[toolCall.toolName] else {
        return toolCall
    }
    return toolCall.with(input: try await refine(toolCall.input))
}

private func parseProviderExecutedDynamicToolCall(
    _ toolCall: LanguageModelV4ToolCall
) async throws -> TypedToolCall {
    let input: JSONValue
    if toolCall.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        input = .object([:])
    } else {
        switch await safeParseJSON(ParseJSONOptions(text: toolCall.input)) {
        case .success(let value, _):
            input = value
        case .failure(let error, _):
            throw InvalidToolInputError(toolName: toolCall.toolName, toolInput: toolCall.input, cause: error)
        }
    }

    return .dynamic(DynamicToolCall(
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: input,
        providerExecuted: true,
        providerMetadata: toolCall.providerMetadata
    ))
}

private func doParseToolCall(
    toolCall: LanguageModelV4ToolCall,
    tools: ToolSet
) async throws -> TypedToolCall {
    let toolName = toolCall.toolName

    guard let tool = tools[toolName] else {
        if toolCall.providerExecuted == true, toolCall.dynamic == true {
            return try await parseProviderExecutedDynamicToolCall(toolCall)
        }
        throw NoSuchToolError(toolName: toolName, availableTools: Array(tools.keys))
    }

    // Many models send an empty string for tools without arguments; validate an empty object instead.
    let parsedValue: JSONValue
    let rawValue: JSONValue
    if toolCall.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        switch await safeValidateTypes(ValidateTypesOptions(value: [String: Any](), schema: tool.inputSchema)) {
        case .success(let value, _):
            parsedValue = value
            rawValue = .object([:])
        case .failure(let error, _):
            throw InvalidToolInputError(toolName: toolName, toolInput: toolCall.input, cause: error)
        }
    } else {
        switch await safeParseJSON(ParseJSONWithSchemaOptions(text: toolCall.input, schema: tool.inputSchema)) {
        case .success(let value, let raw):
            parsedValue = value
            rawValue = (try? jsonValue(from: raw)) ?? value
        case .failure(let error, _):
            throw InvalidToolInputError(toolName: toolName, toolInput: toolCall.input, cause: error)
        }
    }

    let parsed: TypedToolCall
    if tool.type == .dynamic {
        parsed = .dynamic(DynamicToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolName,
            title: tool.title,
            input: parsedValue,
            providerExecuted: toolCall.providerExecuted,
            providerMetadata: toolCall.providerMetadata,
            toolMetadata: tool.metadata
        ))
    } else {
        parsed = .static(StaticToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolName,
            title: tool.title,
            input: parsedValue,
            providerExecuted: toolCall.providerExecuted,
            providerMetadata: toolCall.providerMetadata,
            toolMetadata: tool.metadata
        ))
    }
    return parsed.with(inputSchemaInput: rawValue)
}
