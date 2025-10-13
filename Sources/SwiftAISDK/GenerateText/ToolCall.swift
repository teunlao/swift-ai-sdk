import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tool call types for generation results.

 Port of `@ai-sdk/ai/src/generate-text/tool-call.ts`.

 **Swift adaptation**: TypeScript uses mapped types with `ValueOf` utility to create
 a union of all possible tool calls. Swift uses an enum with associated values instead,
 as Swift doesn't have the same type-level programming capabilities.
 */

/// Static tool call with known tool name and typed input.
/// Represents a tool call where the tool is known at compile time.
public struct StaticToolCall: Sendable {
    /// Type discriminator.
    public let type: String = "tool-call"

    /// The ID of the tool call.
    public let toolCallId: String

    /// The name of the tool that was called.
    public let toolName: String

    /// The input/arguments for the tool call.
    public let input: JSONValue

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    /// Additional provider-specific metadata.
    public let providerMetadata: ProviderMetadata?

    /// Whether this is a dynamic tool call.
    /// For StaticToolCall, this is always false or nil.
    public let dynamic: Bool?

    /// Whether this tool call is invalid (unparsable or tool doesn't exist).
    /// For StaticToolCall, this is always false or nil.
    public let invalid: Bool?

    public init(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerMetadata = providerMetadata
        self.dynamic = false
        self.invalid = false
    }
}

/// Dynamic tool call with unknown tool name or input type.
/// Represents a tool call where the tool is determined at runtime.
public struct DynamicToolCall: Sendable {
    /// Type discriminator.
    public let type: String = "tool-call"

    /// The ID of the tool call.
    public let toolCallId: String

    /// The name of the tool that was called.
    public let toolName: String

    /// The input/arguments for the tool call.
    public let input: JSONValue

    /// Whether this is a dynamic tool call.
    /// For DynamicToolCall, this is always true.
    public let dynamic: Bool = true

    /// Whether the tool was executed by the provider.
    public let providerExecuted: Bool?

    /// Additional provider-specific metadata.
    public let providerMetadata: ProviderMetadata?

    /// True if this is caused by an unparsable tool call or
    /// a tool that does not exist.
    ///
    /// TODO AI SDK 6: separate into a new InvalidToolCall type
    public let invalid: Bool?

    /// The error that caused the tool call to be invalid.
    ///
    /// TODO AI SDK 6: separate into a new InvalidToolCall type
    public let error: (any Error)?

    public init(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil,
        invalid: Bool? = nil,
        error: (any Error)? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerMetadata = providerMetadata
        self.invalid = invalid
        self.error = error
    }
}

/// A tool call that can be either static (typed) or dynamic (untyped).
public enum TypedToolCall: Sendable {
    /// A static tool call with known tool name and typed input.
    case `static`(StaticToolCall)

    /// A dynamic tool call with unknown tool name or input type.
    case dynamic(DynamicToolCall)

    /// The ID of the tool call.
    public var toolCallId: String {
        switch self {
        case .static(let call): return call.toolCallId
        case .dynamic(let call): return call.toolCallId
        }
    }

    /// The name of the tool that was called.
    public var toolName: String {
        switch self {
        case .static(let call): return call.toolName
        case .dynamic(let call): return call.toolName
        }
    }

    /// The input/arguments for the tool call.
    public var input: JSONValue {
        switch self {
        case .static(let call): return call.input
        case .dynamic(let call): return call.input
        }
    }

    /// Whether the tool was executed by the provider.
    public var providerExecuted: Bool? {
        switch self {
        case .static(let call): return call.providerExecuted
        case .dynamic(let call): return call.providerExecuted
        }
    }

    /// Additional provider-specific metadata.
    public var providerMetadata: ProviderMetadata? {
        switch self {
        case .static(let call): return call.providerMetadata
        case .dynamic(let call): return call.providerMetadata
        }
    }

    /// Whether this is a dynamic tool call.
    public var isDynamic: Bool {
        switch self {
        case .static: return false
        case .dynamic: return true
        }
    }

    /// Whether this tool call is invalid.
    public var invalid: Bool? {
        switch self {
        case .static(let call): return call.invalid
        case .dynamic(let call): return call.invalid
        }
    }

    /// The error that caused the tool call to be invalid (for dynamic calls only).
    public var error: (any Error)? {
        switch self {
        case .static: return nil
        case .dynamic(let call): return call.error
        }
    }
}
