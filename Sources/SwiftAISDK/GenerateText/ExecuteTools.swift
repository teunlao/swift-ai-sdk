import Foundation
import AISDKProvider
import AISDKProviderUtils

func executeTools(
    toolCalls: [TypedToolCall],
    tools: ToolSet?,
    tracer: any Tracer,
    telemetry: TelemetrySettings?,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    experimentalContext: JSONValue?
) async throws -> [ToolOutput] {
    guard let tools, !toolCalls.isEmpty else {
        return []
    }

    return try await withThrowingTaskGroup(of: ToolOutput?.self) { group in
        for toolCall in toolCalls {
            group.addTask {
                await executeToolCall(
                    toolCall: toolCall,
                    tools: tools,
                    tracer: tracer,
                    telemetry: telemetry,
                    messages: messages,
                    abortSignal: abortSignal,
                    experimentalContext: experimentalContext
                )
            }
        }

        var outputs: [ToolOutput] = []
        for try await output in group {
            if let output {
                outputs.append(output)
            }
        }
        return outputs
    }
}
