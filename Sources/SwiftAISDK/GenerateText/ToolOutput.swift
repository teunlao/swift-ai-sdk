import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tool output is either a tool result or a tool error.

 Port of `@ai-sdk/ai/src/generate-text/tool-output.ts`.
 */

/// A tool output that can be either a successful result or an error.
public enum ToolOutput: Sendable {
    /// Successful tool execution with result.
    case result(TypedToolResult)

    /// Failed tool execution with error.
    case error(TypedToolError)

    /// The ID of the tool call.
    public var toolCallId: String {
        switch self {
        case .result(let result): return result.toolCallId
        case .error(let error): return error.toolCallId
        }
    }

    /// The name of the tool that was called.
    public var toolName: String {
        switch self {
        case .result(let result): return result.toolName
        case .error(let error): return error.toolName
        }
    }

    /// Whether the tool was executed by the provider.
    public var providerExecuted: Bool? {
        switch self {
        case .result(let result): return result.providerExecuted
        case .error(let error): return error.providerExecuted
        }
    }

    /// Whether this is a dynamic tool output.
    public var isDynamic: Bool {
        switch self {
        case .result(let result): return result.isDynamic
        case .error(let error): return error.isDynamic
        }
    }
}
