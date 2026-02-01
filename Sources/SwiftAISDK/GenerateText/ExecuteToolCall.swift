/**
 Execute a single tool call with telemetry and streaming support.

 Port of `@ai-sdk/ai/src/generate-text/execute-tool-call.ts`.
 */
import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Execute a tool call and return either a tool result or a tool error.

 Port of `@ai-sdk/ai/src/generate-text/execute-tool-call.ts`.
 */
public func executeToolCall(
    toolCall: TypedToolCall,
    tools: ToolSet?,
    tracer: any Tracer,
    telemetry: TelemetrySettings?,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    experimentalContext: JSONValue?,
    onPreliminaryToolResult: (@Sendable (TypedToolResult) -> Void)? = nil
) async -> ToolOutput? {
    let toolName = toolCall.toolName
    let toolCallId = toolCall.toolCallId
    let input = toolCall.input

    guard
        let tool = tools?[toolName],
        let execute = tool.execute
    else {
        return nil
    }

    var telemetryAttributes: [String: ResolvableAttributeValue?] = [:]
    for (key, value) in assembleOperationName(operationId: "ai.toolCall", telemetry: telemetry) {
        telemetryAttributes[key] = .value(value)
    }
    telemetryAttributes["ai.toolCall.name"] = .value(.string(toolName))
    telemetryAttributes["ai.toolCall.id"] = .value(.string(toolCallId))
    telemetryAttributes["ai.toolCall.args"] = .output {
        guard let stringValue = jsonString(from: input) else {
            return nil
        }
        return .string(stringValue)
    }

    let spanAttributes = try? await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: telemetryAttributes
    )

    return await recordSpan(
        name: "ai.toolCall",
        tracer: tracer,
        attributes: spanAttributes ?? [:]
    ) { span in
        do {
            let stream = executeTool(
                execute: execute,
                input: input,
                options: ToolCallOptions(
                    toolCallId: toolCallId,
                    messages: messages,
                    abortSignal: abortSignal,
                    experimentalContext: experimentalContext
                )
            )

            var finalOutput: JSONValue?

            for try await part in stream {
                switch part {
                case .preliminary(let output):
                    let typed = makeToolResult(
                        from: toolCall,
                        output: output,
                        providerExecuted: toolCall.providerExecuted,
                        preliminary: true
                    )
                    onPreliminaryToolResult?(typed)

                case .final(let output):
                    finalOutput = output
                }
            }

            let typedResult = makeToolResult(
                from: toolCall,
                output: finalOutput ?? .null,
                providerExecuted: toolCall.providerExecuted,
                preliminary: nil
            )

            if let finalOutput {
                let resultAttributes = try? await selectTelemetryAttributes(
                    telemetry: telemetry,
                    attributes: [
                        "ai.toolCall.result": .output {
                            guard let stringValue = jsonString(from: finalOutput) else {
                                return nil
                            }
                            return .string(stringValue)
                        }
                    ]
                )
                if let resultAttributes {
                    span.setAttributes(resultAttributes)
                }
            }

            return .result(typedResult)
        } catch {
            recordErrorOnSpan(span, error: error)

            let errorResult = makeToolError(
                from: toolCall,
                error: error,
                providerExecuted: toolCall.providerExecuted
            )

            return .error(errorResult)
        }
    }
}

// MARK: - Helpers

private func makeToolResult(
    from toolCall: TypedToolCall,
    output: JSONValue,
    providerExecuted: Bool?,
    preliminary: Bool?
) -> TypedToolResult {
    switch toolCall {
    case .static(let call):
        return .static(
            StaticToolResult(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                title: call.title,
                input: call.input,
                output: output,
                providerExecuted: providerExecuted,
                preliminary: preliminary
            )
        )
    case .dynamic(let call):
        return .dynamic(
            DynamicToolResult(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                title: call.title,
                input: call.input,
                output: output,
                providerExecuted: providerExecuted,
                preliminary: preliminary
            )
        )
    }
}

private func makeToolError(
    from toolCall: TypedToolCall,
    error: any Error,
    providerExecuted: Bool?
) -> TypedToolError {
    switch toolCall {
    case .static(let call):
        return .static(
            StaticToolError(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                title: call.title,
                input: call.input,
                error: error,
                providerExecuted: providerExecuted
            )
        )
    case .dynamic(let call):
        return .dynamic(
            DynamicToolError(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                title: call.title,
                input: call.input,
                error: error,
                providerExecuted: providerExecuted
            )
        )
    }
}

private func jsonString(from value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}
