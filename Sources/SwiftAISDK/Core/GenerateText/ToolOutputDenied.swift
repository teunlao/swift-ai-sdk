import Foundation

/**
 Tool output when the tool execution has been denied.

 Port of `@ai-sdk/ai/src/generate-text/tool-output-denied.ts`.

 **Swift adaptation**: TypeScript uses mapped types with `ValueOf` utility.
 Swift uses a simple struct instead, as the type-level programming is not the same.
 */

/// Tool output when the tool execution has been denied.
public struct ToolOutputDenied: Sendable {
    /// Type discriminator.
    public let type: String = "tool-output-denied"

    /// The ID of the tool call that was denied.
    public let toolCallId: String

    /// The name of the tool that was denied.
    public let toolName: String

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    /// Whether this is a dynamic tool output.
    /// For denied outputs, this is always false or nil.
    public let dynamic: Bool?

    public init(
        toolCallId: String,
        toolName: String,
        providerExecuted: Bool? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.providerExecuted = providerExecuted
        self.dynamic = false
    }
}
