/**
 Check if a tool call requires approval before execution.

 Port of `@ai-sdk/ai/src/generate-text/is-approval-needed.ts`.

 Determines whether a tool call needs user approval based on the tool's
 needsApproval configuration, which can be:
 - nil: no approval needed (default)
 - .always: always requires approval
 - .never: never requires approval
 - .conditional: dynamic approval check based on tool call details
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Check if a tool call requires approval
/// - Parameters:
///   - tool: The tool being called
///   - toolCall: The specific tool call instance
///   - messages: Message history
///   - experimentalContext: Additional context data
/// - Returns: true if approval is needed, false otherwise
public func isApprovalNeeded(
    tool: Tool,
    toolCall: TypedToolCall,
    messages: [ModelMessage],
    experimentalContext: JSONValue?
) async -> Bool {
    guard let needsApproval = tool.needsApproval else {
        return false
    }

    switch needsApproval {
    case .always:
        return true

    case .never:
        return false

    case .conditional(let checkApproval):
        do {
            return try await checkApproval(
                toolCall.input,
                ToolCallApprovalOptions(
                    toolCallId: toolCall.toolCallId,
                    messages: messages,
                    experimentalContext: experimentalContext
                )
            )
        } catch {
            // If approval check fails, default to requiring approval
            return true
        }
    }
}
