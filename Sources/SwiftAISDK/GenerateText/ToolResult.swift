import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tool result types for generation results.

 Port of `@ai-sdk/ai/src/generate-text/tool-result.ts`.

 **Swift adaptation**: TypeScript uses mapped types with `ValueOf` utility to create
 a union of all possible tool results. Swift uses an enum with associated values instead.
 */

/// Static tool result with known tool name and typed input/output.
/// Represents a tool result where the tool is known at compile time.
public struct StaticToolResult: Sendable {
    /// Type discriminator.
    public let type: String = "tool-result"

    /// The ID of the tool call.
    public let toolCallId: String

    /// The name of the tool that was called.
    public let toolName: String

    /// Optional display title for the tool.
    public let title: String?

    /// The input that was passed to the tool.
    public let input: JSONValue

    /// The output returned by the tool.
    public let output: JSONValue

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    /// Whether this is a dynamic tool result.
    /// For StaticToolResult, this is always false or nil.
    public let dynamic: Bool?

    /// Whether this is a preliminary result (for streaming tool execution).
    public let preliminary: Bool?

    /// Provider-specific metadata for the tool result.
    public let providerMetadata: ProviderMetadata?

    public init(
        toolCallId: String,
        toolName: String,
        title: String? = nil,
        input: JSONValue,
        output: JSONValue,
        providerExecuted: Bool? = nil,
        preliminary: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.title = title
        self.input = input
        self.output = output
        self.providerExecuted = providerExecuted
        self.dynamic = false
        self.preliminary = preliminary
        self.providerMetadata = providerMetadata
    }
}

/// Dynamic tool result with unknown tool name or input/output type.
/// Represents a tool result where the tool is determined at runtime.
public struct DynamicToolResult: Sendable {
    /// Type discriminator.
    public let type: String = "tool-result"

    /// The ID of the tool call.
    public let toolCallId: String

    /// The name of the tool that was called.
    public let toolName: String

    /// Optional display title for the tool.
    public let title: String?

    /// The input that was passed to the tool.
    public let input: JSONValue

    /// The output returned by the tool.
    public let output: JSONValue

    /// Whether this is a dynamic tool result.
    /// For DynamicToolResult, this is always true.
    public let dynamic: Bool = true

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    /// Whether this is a preliminary result (for streaming tool execution).
    public let preliminary: Bool?

    /// Provider-specific metadata for the tool result.
    public let providerMetadata: ProviderMetadata?

    public init(
        toolCallId: String,
        toolName: String,
        title: String? = nil,
        input: JSONValue,
        output: JSONValue,
        providerExecuted: Bool? = nil,
        preliminary: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.title = title
        self.input = input
        self.output = output
        self.providerExecuted = providerExecuted
        self.preliminary = preliminary
        self.providerMetadata = providerMetadata
    }
}

/// A tool result that can be either static (typed) or dynamic (untyped).
public enum TypedToolResult: Sendable {
    /// A static tool result with known tool name and typed input/output.
    case `static`(StaticToolResult)

    /// A dynamic tool result with unknown tool name or input/output type.
    case dynamic(DynamicToolResult)

    /// The ID of the tool call.
    public var toolCallId: String {
        switch self {
        case .static(let result): return result.toolCallId
        case .dynamic(let result): return result.toolCallId
        }
    }

    /// The name of the tool that was called.
    public var toolName: String {
        switch self {
        case .static(let result): return result.toolName
        case .dynamic(let result): return result.toolName
        }
    }

    /// The input that was passed to the tool.
    public var input: JSONValue {
        switch self {
        case .static(let result): return result.input
        case .dynamic(let result): return result.input
        }
    }

    /// Optional display title for the tool.
    public var title: String? {
        switch self {
        case .static(let result): return result.title
        case .dynamic(let result): return result.title
        }
    }

    /// The output returned by the tool.
    public var output: JSONValue {
        switch self {
        case .static(let result): return result.output
        case .dynamic(let result): return result.output
        }
    }

    /// Whether the tool was executed by the provider.
    public var providerExecuted: Bool? {
        switch self {
        case .static(let result): return result.providerExecuted
        case .dynamic(let result): return result.providerExecuted
        }
    }

    /// Whether this is a dynamic tool result.
    public var isDynamic: Bool {
        switch self {
        case .static: return false
        case .dynamic: return true
        }
    }

    /// Whether this is a preliminary result (for streaming tool execution).
    public var preliminary: Bool? {
        switch self {
        case .static(let result): return result.preliminary
        case .dynamic(let result): return result.preliminary
        }
    }

    /// Provider-specific metadata for the tool result.
    public var providerMetadata: ProviderMetadata? {
        switch self {
        case .static(let result): return result.providerMetadata
        case .dynamic(let result): return result.providerMetadata
        }
    }
}
