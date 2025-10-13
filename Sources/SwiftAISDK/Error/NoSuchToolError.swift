import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when a model attempts to call a tool that is not available.

 Port of `@ai-sdk/ai/src/error/no-such-tool-error.ts`.
 */
public struct NoSuchToolError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoSuchToolError"

    public let name = "AI_NoSuchToolError"
    public let message: String
    public let cause: (any Error)? = nil

    /// The name of the tool that the model tried to call
    public let toolName: String

    /// The list of available tools, if any
    public let availableTools: [String]?

    public init(
        toolName: String,
        availableTools: [String]? = nil,
        message: String? = nil
    ) {
        self.toolName = toolName
        self.availableTools = availableTools

        if let message = message {
            self.message = message
        } else {
            if let tools = availableTools {
                self.message = "Model tried to call unavailable tool '\(toolName)'. Available tools: \(tools.joined(separator: ", "))."
            } else {
                self.message = "Model tried to call unavailable tool '\(toolName)'. No tools are available."
            }
        }
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
