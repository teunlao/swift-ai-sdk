/**
 Parse language model tool calls and apply optional repair logic.

 Port of `@ai-sdk/ai/src/generate-text/parse-tool-call.ts`.
 */
import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Parse a tool call from the language model response.

 Port of `@ai-sdk/ai/src/generate-text/parse-tool-call.ts`.

 This function:
 1. Attempts to parse the tool call with `doParseToolCall()`
 2. If parsing fails and a repair function is provided, attempts repair
 3. Returns either a valid typed tool call or an invalid dynamic tool call with error

 ## Upstream Behavior

 TypeScript:
 ```typescript
 export async function parseToolCall<TOOLS extends ToolSet>({
   toolCall,
   tools,
   repairToolCall,
   system,
   messages,
 }): Promise<TypedToolCall<TOOLS>> {
   try {
     if (tools == null) {
       throw new NoSuchToolError({ toolName: toolCall.toolName });
     }

     try {
       return await doParseToolCall({ toolCall, tools });
     } catch (error) {
       if (repairToolCall == null || !(NoSuchToolError.isInstance(error) || InvalidToolInputError.isInstance(error))) {
         throw error;
       }

       let repairedToolCall = await repairToolCall({ toolCall, tools, inputSchema, system, messages, error });

       if (repairedToolCall == null) {
         throw error;
       }

       return await doParseToolCall({ toolCall: repairedToolCall, tools });
     }
   } catch (error) {
     // Return invalid dynamic tool call
     const parsedInput = await safeParseJSON({ text: toolCall.input });
     const input = parsedInput.success ? parsedInput.value : toolCall.input;

     return {
       type: 'tool-call',
       toolCallId: toolCall.toolCallId,
       toolName: toolCall.toolName,
       input,
       dynamic: true,
       invalid: true,
       error,
     };
   }
 }
 ```

 Swift:
 ```swift
 let typedToolCall = try await parseToolCall(
     toolCall: languageModelToolCall,
     tools: tools,
     repairToolCall: repairFunction,
     system: systemPrompt,
     messages: messages
 )
 ```

 - Parameters:
   - toolCall: The tool call from the language model
   - tools: The available tools (dictionary of tool name to Tool)
   - repairToolCall: Optional function to repair failed tool calls
   - system: Optional system prompt
   - messages: The messages in the current generation step

 - Returns: A `TypedToolCall` (either static or dynamic, may be invalid)

 - Throws: Never throws - errors are captured in invalid dynamic tool calls
 */
public func parseToolCall(
    toolCall: LanguageModelV3ToolCall,
    tools: ToolSet?,
    repairToolCall: ToolCallRepairFunction?,
    system: String?,
    messages: [ModelMessage]
) async -> TypedToolCall {
    do {
        guard let tools = tools else {
            // Provider-executed dynamic tools are not part of our list of tools:
            if toolCall.providerExecuted == true, toolCall.dynamic == true {
                return try await parseProviderExecutedDynamicToolCall(toolCall)
            }

            throw NoSuchToolError(toolName: toolCall.toolName)
        }

        do {
            return try await doParseToolCall(toolCall: toolCall, tools: tools)
        } catch {
            // Only attempt repair for NoSuchToolError or InvalidToolInputError
            if repairToolCall == nil ||
               !(NoSuchToolError.isInstance(error) || InvalidToolInputError.isInstance(error)) {
                throw error
            }

            // Attempt repair
            let repairOptions = ToolCallRepairOptions(
                system: system,
                messages: messages,
                toolCall: toolCall,
                tools: tools,
                inputSchema: { toolName in
                    guard let tool = tools[toolName] else {
                        throw NoSuchToolError(toolName: toolName)
                    }
                    let schema = try await asSchema(tool.inputSchema).jsonSchema()
                    // Convert JSONValue to [String: JSONValue] (schema is always an object)
                    guard case .object(let schemaDict) = schema else {
                        throw InvalidToolInputError(
                            toolName: toolName,
                            toolInput: "",
                            cause: NSError(domain: "SchemaError", code: -1, userInfo: [
                                NSLocalizedDescriptionKey: "Schema is not an object"
                            ])
                        )
                    }
                    return schemaDict
                },
                error: error
            )

            var repairedToolCall: LanguageModelV3ToolCall?
            do {
                repairedToolCall = try await repairToolCall?(repairOptions)
            } catch let repairError {
                // Repair itself failed - wrap original error in enum
                let originalError: ToolCallOriginalError
                if let noSuchError = error as? NoSuchToolError {
                    originalError = .noSuchTool(noSuchError)
                } else if let invalidInputError = error as? InvalidToolInputError {
                    originalError = .invalidToolInput(invalidInputError)
                } else {
                    // Should not happen - we checked error type above
                    throw error
                }
                throw ToolCallRepairError(originalError: originalError, cause: repairError)
            }

            // No repaired tool call returned
            guard let repairedToolCall = repairedToolCall else {
                throw error
            }

            return try await doParseToolCall(toolCall: repairedToolCall, tools: tools)
        }
    } catch {
        // Use parsed input when possible
        let parsedInput = await safeParseJSON(ParseJSONOptions(text: toolCall.input))
        let input: JSONValue
        switch parsedInput {
        case .success(let value, _):
            input = value
        case .failure:
            input = JSONValue.string(toolCall.input)
        }

        // Return invalid dynamic tool call
        // TODO AI SDK 6: special invalid tool call parts
        return .dynamic(DynamicToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: input,
            providerExecuted: toolCall.providerExecuted,
            providerMetadata: toolCall.providerMetadata,
            invalid: true,
            error: error
        ))
    }
}

private func parseProviderExecutedDynamicToolCall(
    _ toolCall: LanguageModelV3ToolCall
) async throws -> TypedToolCall {
    let trimmed = toolCall.input.trimmingCharacters(in: .whitespacesAndNewlines)

    let input: JSONValue
    if trimmed.isEmpty {
        input = .object([:])
    } else {
        let parsed = await safeParseJSON(ParseJSONOptions(text: toolCall.input))
        switch parsed {
        case .success(let value, _):
            input = value
        case .failure(let error, _):
            throw InvalidToolInputError(
                toolName: toolCall.toolName,
                toolInput: toolCall.input,
                cause: error
            )
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

/**
 Internal helper to parse a tool call without error handling.

 Port of `@ai-sdk/ai/src/generate-text/parse-tool-call.ts` - `doParseToolCall()`.

 - Parameters:
   - toolCall: The tool call from the language model
   - tools: The available tools

 - Returns: A `TypedToolCall`

 - Throws: `NoSuchToolError` if tool doesn't exist, `InvalidToolInputError` if input is invalid
 */
private func doParseToolCall(
    toolCall: LanguageModelV3ToolCall,
    tools: ToolSet
) async throws -> TypedToolCall {
    let toolName = toolCall.toolName

    guard let tool = tools[toolName] else {
        // Provider-executed dynamic tools are not part of our list of tools:
        if toolCall.providerExecuted == true, toolCall.dynamic == true {
            return try await parseProviderExecutedDynamicToolCall(toolCall)
        }

        throw NoSuchToolError(
            toolName: toolCall.toolName,
            availableTools: Array(tools.keys)
        )
    }

    // When the tool call has no arguments, we try passing an empty object to the schema
    // (many LLMs generate empty strings for tool calls with no arguments)
    let parsedValue: JSONValue
    if toolCall.input.trimmingCharacters(in: .whitespaces).isEmpty {
        let validateResult = await safeValidateTypes(ValidateTypesOptions(value: JSONValue.object([:]), schema: tool.inputSchema))
        switch validateResult {
        case .success(let value, _):
            parsedValue = value
        case .failure(let error, _):
            throw InvalidToolInputError(
                toolName: toolName,
                toolInput: toolCall.input,
                cause: error
            )
        }
    } else {
        let parseResult = await safeParseJSON(ParseJSONWithSchemaOptions(text: toolCall.input, schema: tool.inputSchema))
        switch parseResult {
        case .success(let value, _):
            parsedValue = value
        case .failure(let error, _):
            throw InvalidToolInputError(
                toolName: toolName,
                toolInput: toolCall.input,
                cause: error
            )
        }
    }

    // Return static or dynamic tool call based on tool type
    if tool.type == .dynamic {
        return .dynamic(DynamicToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: parsedValue,
            providerExecuted: toolCall.providerExecuted,
            providerMetadata: toolCall.providerMetadata,
            invalid: false,
            error: nil
        ))
    } else {
        return .static(StaticToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolName,
            input: parsedValue,
            providerExecuted: toolCall.providerExecuted,
            providerMetadata: toolCall.providerMetadata
        ))
    }
}
