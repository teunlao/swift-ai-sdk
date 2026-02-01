import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tool error types for generation results.

 Port of `@ai-sdk/ai/src/generate-text/tool-error.ts`.

 **Swift adaptation**: TypeScript uses mapped types with `ValueOf` utility to create
 a union of all possible tool errors. Swift uses an enum with associated values instead.
 */

/// Static tool error with known tool name and typed input.
/// Represents a tool error where the tool is known at compile time.
public struct StaticToolError: Sendable {
    /// Type discriminator.
    public let type: String = "tool-error"

    /// The ID of the tool call.
    public let toolCallId: String

    /// The name of the tool that was called.
    public let toolName: String

    /// Optional display title for the tool.
    public let title: String?

    /// The input that was passed to the tool.
    public let input: JSONValue

    /// The error that occurred during tool execution.
    public let error: any Error

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    /// Whether this is a dynamic tool error.
    /// For StaticToolError, this is always false or nil.
    public let dynamic: Bool?

    public init(
        toolCallId: String,
        toolName: String,
        title: String? = nil,
        input: JSONValue,
        error: any Error,
        providerExecuted: Bool? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.title = title
        self.input = input
        self.error = error
        self.providerExecuted = providerExecuted
        self.dynamic = false
    }
}

/// Dynamic tool error with unknown tool name or input type.
/// Represents a tool error where the tool is determined at runtime.
public struct DynamicToolError: Sendable {
    /// Type discriminator.
    public let type: String = "tool-error"

    /// The ID of the tool call.
    public let toolCallId: String

    /// The name of the tool that was called.
    public let toolName: String

    /// Optional display title for the tool.
    public let title: String?

    /// The input that was passed to the tool.
    public let input: JSONValue

    /// The error that occurred during tool execution.
    public let error: any Error

    /// Whether this is a dynamic tool error.
    /// For DynamicToolError, this is always true.
    public let dynamic: Bool = true

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    public init(
        toolCallId: String,
        toolName: String,
        title: String? = nil,
        input: JSONValue,
        error: any Error,
        providerExecuted: Bool? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.title = title
        self.input = input
        self.error = error
        self.providerExecuted = providerExecuted
    }
}

/// A tool error that can be either static (typed) or dynamic (untyped).
public enum TypedToolError: Sendable {
    /// A static tool error with known tool name and typed input.
    case `static`(StaticToolError)

    /// A dynamic tool error with unknown tool name or input type.
    case dynamic(DynamicToolError)

    /// The ID of the tool call.
    public var toolCallId: String {
        switch self {
        case .static(let error): return error.toolCallId
        case .dynamic(let error): return error.toolCallId
        }
    }

    /// The name of the tool that was called.
    public var toolName: String {
        switch self {
        case .static(let error): return error.toolName
        case .dynamic(let error): return error.toolName
        }
    }

    /// The input that was passed to the tool.
    public var input: JSONValue {
        switch self {
        case .static(let error): return error.input
        case .dynamic(let error): return error.input
        }
    }

    /// Optional display title for the tool.
    public var title: String? {
        switch self {
        case .static(let error): return error.title
        case .dynamic(let error): return error.title
        }
    }

    /// The error that occurred during tool execution.
    public var error: any Error {
        switch self {
        case .static(let error): return error.error
        case .dynamic(let error): return error.error
        }
    }

    /// Whether the tool was executed by the provider.
    public var providerExecuted: Bool? {
        switch self {
        case .static(let error): return error.providerExecuted
        case .dynamic(let error): return error.providerExecuted
        }
    }

    /// Whether this is a dynamic tool error.
    public var isDynamic: Bool {
        switch self {
        case .static: return false
        case .dynamic: return true
        }
    }
}
