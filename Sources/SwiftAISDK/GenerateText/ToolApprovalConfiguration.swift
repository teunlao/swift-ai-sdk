import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Approval decision for a tool call.

 Port of `ToolApprovalStatus` from `@ai-sdk/ai/src/generate-text/tool-approval-configuration.ts`.
 A `nil` status means `notApplicable`.
 */
public enum ToolApprovalStatus: Sendable, Equatable {
    /// No approval applies: the tool call executes.
    case notApplicable
    /// Approved automatically.
    case approved(reason: String? = nil)
    /// Denied automatically.
    case denied(reason: String? = nil)
    /// The user must approve the tool call.
    case userApproval(reason: String? = nil)

    var reason: String? {
        switch self {
        case .notApplicable: return nil
        case .approved(let reason), .denied(let reason), .userApproval(let reason): return reason
        }
    }
}

/// Options passed to a per-tool approval function.
public struct SingleToolApprovalOptions: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String
    /// Messages sent to the model to initiate the response that contained the tool call.
    public let messages: [ModelMessage]
    /// The validated context of the tool.
    public let toolContext: Context?
    /// The runtime context of the call.
    public let runtimeContext: Context

    public init(toolCallId: String, messages: [ModelMessage], toolContext: Context?, runtimeContext: Context) {
        self.toolCallId = toolCallId
        self.messages = messages
        self.toolContext = toolContext
        self.runtimeContext = runtimeContext
    }
}

/// Options passed to a generic approval function.
public struct GenericToolApprovalOptions: Sendable {
    public let toolCall: TypedToolCall
    public let tools: ToolSet?
    public let toolsContext: ToolsContext
    public let runtimeContext: Context
    public let messages: [ModelMessage]

    public init(
        toolCall: TypedToolCall,
        tools: ToolSet?,
        toolsContext: ToolsContext,
        runtimeContext: Context,
        messages: [ModelMessage]
    ) {
        self.toolCall = toolCall
        self.tools = tools
        self.toolsContext = toolsContext
        self.runtimeContext = runtimeContext
        self.messages = messages
    }
}

/// Approval of one tool: a fixed status or a function of the tool input.
public enum ToolApprovalRule: Sendable {
    case status(ToolApprovalStatus)
    case resolve(@Sendable (JSONValue, SingleToolApprovalOptions) async throws -> ToolApprovalStatus?)
}

/**
 Tool approval configuration of a generation call. Takes precedence over the
 tools' own `needsApproval`.

 Port of `ToolApprovalConfiguration` from `@ai-sdk/ai/src/generate-text/tool-approval-configuration.ts`.
 */
public enum ToolApprovalConfiguration: Sendable {
    /// Approval per tool name; tools without an entry fall back to `needsApproval`.
    case perTool([String: ToolApprovalRule])
    /// One function deciding every tool call.
    case generic(@Sendable (GenericToolApprovalOptions) async throws -> ToolApprovalStatus?)
}

/**
 Resolves the approval status of a tool call.

 Port of `@ai-sdk/ai/src/generate-text/resolve-tool-approval.ts`.
 */
func resolveToolApproval(
    tools: ToolSet?,
    toolCall: TypedToolCall,
    toolApproval: ToolApprovalConfiguration?,
    messages: [ModelMessage],
    toolsContext: ToolsContext,
    runtimeContext: Context
) async throws -> ToolApprovalStatus {
    let toolName = toolCall.toolName
    let tool = tools?[toolName]

    switch toolApproval {
    case .generic(let resolve):
        return try await resolve(GenericToolApprovalOptions(
            toolCall: toolCall,
            tools: tools,
            toolsContext: toolsContext,
            runtimeContext: runtimeContext,
            messages: messages
        )) ?? .notApplicable

    case .perTool(let rules):
        if let rule = rules[toolName] {
            switch rule {
            case .status(let status):
                return status
            case .resolve(let resolve):
                let toolContext = try await validateToolContext(
                    toolName: toolName,
                    context: toolsContext[toolName],
                    contextSchema: tool?.contextSchema
                )
                return try await resolve(toolCall.input, SingleToolApprovalOptions(
                    toolCallId: toolCall.toolCallId,
                    messages: messages,
                    toolContext: toolContext,
                    runtimeContext: runtimeContext
                )) ?? .notApplicable
            }
        }

    case nil:
        break
    }

    guard let needsApproval = tool?.needsApproval else {
        return .notApplicable
    }

    switch needsApproval {
    case .always:
        return .userApproval()
    case .never:
        return .notApplicable
    case .conditional(let decide):
        let context = try await validateToolContext(
            toolName: toolName,
            context: toolsContext[toolName],
            contextSchema: tool?.contextSchema
        )
        let needs = try await decide(toolCall.input, ToolCallApprovalOptions(
            toolCallId: toolCall.toolCallId,
            messages: messages,
            context: context
        ))
        return needs ? .userApproval() : .notApplicable
    }
}
