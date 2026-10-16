import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tool call types for generation results.

 Port of `@ai-sdk/ai/src/generate-text/tool-call.ts`. The upstream union of
 static and dynamic tool calls is an enum.
 */
public struct StaticToolCall: Sendable {
    public let type: String = "tool-call"
    public let toolCallId: String
    public let toolName: String
    public let title: String?
    public let input: JSONValue
    public let providerExecuted: Bool?
    public let providerMetadata: ProviderMetadata?
    /// Metadata of the tool that was called (`Tool.metadata`).
    public let toolMetadata: [String: JSONValue]?
    public let dynamic: Bool?
    public let invalid: Bool?

    /// The value the input schema received before transforming it, when it differs from `input`.
    var inputSchemaInput: JSONValue?

    public init(
        toolCallId: String,
        toolName: String,
        title: String? = nil,
        input: JSONValue,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil,
        toolMetadata: [String: JSONValue]? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.title = title
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerMetadata = providerMetadata
        self.toolMetadata = toolMetadata
        self.dynamic = false
        self.invalid = false
    }
}

public struct DynamicToolCall: Sendable {
    public let type: String = "tool-call"
    public let toolCallId: String
    public let toolName: String
    public let title: String?
    public let input: JSONValue
    public let dynamic: Bool = true
    public let providerExecuted: Bool?
    public let providerMetadata: ProviderMetadata?
    /// Metadata of the tool that was called (`Tool.metadata`).
    public let toolMetadata: [String: JSONValue]?
    public let invalid: Bool?
    public let error: (any Error)?

    /// The value the input schema received before transforming it, when it differs from `input`.
    var inputSchemaInput: JSONValue?

    public init(
        toolCallId: String,
        toolName: String,
        title: String? = nil,
        input: JSONValue,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil,
        toolMetadata: [String: JSONValue]? = nil,
        invalid: Bool? = nil,
        error: (any Error)? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.title = title
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerMetadata = providerMetadata
        self.toolMetadata = toolMetadata
        self.invalid = invalid
        self.error = error
    }
}

public enum TypedToolCall: Sendable {
    case `static`(StaticToolCall)
    case dynamic(DynamicToolCall)

    public var toolCallId: String {
        switch self {
        case .static(let call): return call.toolCallId
        case .dynamic(let call): return call.toolCallId
        }
    }

    public var toolName: String {
        switch self {
        case .static(let call): return call.toolName
        case .dynamic(let call): return call.toolName
        }
    }

    public var input: JSONValue {
        switch self {
        case .static(let call): return call.input
        case .dynamic(let call): return call.input
        }
    }

    public var title: String? {
        switch self {
        case .static(let call): return call.title
        case .dynamic(let call): return call.title
        }
    }

    public var providerExecuted: Bool? {
        switch self {
        case .static(let call): return call.providerExecuted
        case .dynamic(let call): return call.providerExecuted
        }
    }

    public var providerMetadata: ProviderMetadata? {
        switch self {
        case .static(let call): return call.providerMetadata
        case .dynamic(let call): return call.providerMetadata
        }
    }

    public var toolMetadata: [String: JSONValue]? {
        switch self {
        case .static(let call): return call.toolMetadata
        case .dynamic(let call): return call.toolMetadata
        }
    }

    public var isDynamic: Bool {
        if case .dynamic = self { return true }
        return false
    }

    public var invalid: Bool? {
        switch self {
        case .static(let call): return call.invalid
        case .dynamic(let call): return call.invalid
        }
    }

    public var error: (any Error)? {
        switch self {
        case .static: return nil
        case .dynamic(let call): return call.error
        }
    }

    var inputSchemaInput: JSONValue? {
        switch self {
        case .static(let call): return call.inputSchemaInput
        case .dynamic(let call): return call.inputSchemaInput
        }
    }

    /// The same call with a different input (used by input refinement and approvals).
    func with(input: JSONValue) -> TypedToolCall {
        switch self {
        case .static(let call):
            var updated = StaticToolCall(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                title: call.title,
                input: input,
                providerExecuted: call.providerExecuted,
                providerMetadata: call.providerMetadata,
                toolMetadata: call.toolMetadata
            )
            updated.inputSchemaInput = call.inputSchemaInput
            return .static(updated)
        case .dynamic(let call):
            var updated = DynamicToolCall(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                title: call.title,
                input: input,
                providerExecuted: call.providerExecuted,
                providerMetadata: call.providerMetadata,
                toolMetadata: call.toolMetadata,
                invalid: call.invalid,
                error: call.error
            )
            updated.inputSchemaInput = call.inputSchemaInput
            return .dynamic(updated)
        }
    }

    func with(inputSchemaInput: JSONValue?) -> TypedToolCall {
        switch self {
        case .static(var call):
            call.inputSchemaInput = inputSchemaInput
            return .static(call)
        case .dynamic(var call):
            call.inputSchemaInput = inputSchemaInput
            return .dynamic(call)
        }
    }
}
