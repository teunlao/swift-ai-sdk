import Foundation
import AISDKProvider
import AISDKProviderUtils

func makeToolContentPart(
    output: ToolOutput,
    tools: ToolSet?
) -> ToolContentPart {
    switch output {
    case .result(let result):
        let modelOutput = createToolModelOutput(
            output: result.output,
            tool: tools?[result.toolName],
            errorMode: .none
        )
        let part = ToolResultPart(
            toolCallId: result.toolCallId,
            toolName: result.toolName,
            output: modelOutput,
            providerOptions: nil
        )
        return .toolResult(part)

    case .error(let error):
        let modelOutput = createToolModelOutput(
            output: error.error,
            tool: tools?[error.toolName],
            errorMode: .json
        )
        let part = ToolResultPart(
            toolCallId: error.toolCallId,
            toolName: error.toolName,
            output: modelOutput,
            providerOptions: nil
        )
        return .toolResult(part)
    }
}


func makeInvalidToolCallError(from toolCall: TypedToolCall) -> TypedToolError {
    let message = errorMessage(from: toolCall.error)
    let error = NSError(
        domain: "StreamText",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )

    return .dynamic(
        DynamicToolError(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            error: error,
            providerExecuted: toolCall.providerExecuted
        )
    )
}

func errorMessage(from error: (any Error)?) -> String {
    guard let error else { return "Unknown error" }
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(describing: error)
}


func makeProviderToolResult(
    storedCall: TypedToolCall?,
    fallbackToolName: String,
    toolCallId: String,
    input: JSONValue,
    output: JSONValue,
    providerExecuted: Bool?,
    preliminary: Bool?,
    providerMetadata: ProviderMetadata?
) -> TypedToolResult {
    if let storedCall {
        switch storedCall {
        case .static(let call):
            return .static(
                StaticToolResult(
                    toolCallId: call.toolCallId,
                    toolName: call.toolName,
                    input: call.input,
                    output: output,
                    providerExecuted: providerExecuted,
                    preliminary: preliminary,
                    providerMetadata: providerMetadata
                )
            )
        case .dynamic(let call):
            return .dynamic(
                DynamicToolResult(
                    toolCallId: call.toolCallId,
                    toolName: call.toolName,
                    input: call.input,
                    output: output,
                    providerExecuted: providerExecuted,
                    preliminary: preliminary,
                    providerMetadata: providerMetadata
                )
            )
        }
    }

    return .dynamic(
        DynamicToolResult(
            toolCallId: toolCallId,
            toolName: fallbackToolName,
            input: input,
            output: output,
            providerExecuted: providerExecuted,
            preliminary: preliminary,
            providerMetadata: providerMetadata
        )
    )
}

func makeProviderToolError(
    storedCall: TypedToolCall?,
    fallbackToolName: String,
    toolCallId: String,
    input: JSONValue,
    providerExecuted: Bool?,
    error: any Error
) -> TypedToolError {
    if let storedCall {
        switch storedCall {
        case .static(let call):
            return .static(
                StaticToolError(
                    toolCallId: call.toolCallId,
                    toolName: call.toolName,
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
                    input: call.input,
                    error: error,
                    providerExecuted: providerExecuted
                )
            )
        }
    }

    return .dynamic(
        DynamicToolError(
            toolCallId: toolCallId,
            toolName: fallbackToolName,
            input: input,
            error: error,
            providerExecuted: providerExecuted
        )
    )
}
