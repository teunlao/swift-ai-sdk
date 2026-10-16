import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Options of a tool call repair function.

 Port of `@ai-sdk/ai/src/generate-text/tool-call-repair-function.ts`.
 */
public struct ToolCallRepairOptions: Sendable {
    /// The instructions of the step.
    public let instructions: Instructions?

    /// The messages of the step.
    public let messages: [ModelMessage]

    /// The tool call that failed to parse.
    public let toolCall: LanguageModelV4ToolCall

    /// The available tools.
    public let tools: ToolSet

    /// Returns the JSON Schema of a tool's input.
    public let inputSchema: @Sendable (String) async throws -> JSONValue

    /// The parse error: `NoSuchToolError` or `InvalidToolInputError`.
    public let error: any Error

    /// Abort signal of the generation.
    public let abortSignal: (@Sendable () -> Bool)?

    public init(
        instructions: Instructions?,
        messages: [ModelMessage],
        toolCall: LanguageModelV4ToolCall,
        tools: ToolSet,
        inputSchema: @escaping @Sendable (String) async throws -> JSONValue,
        error: any Error,
        abortSignal: (@Sendable () -> Bool)? = nil
    ) {
        self.instructions = instructions
        self.messages = messages
        self.toolCall = toolCall
        self.tools = tools
        self.inputSchema = inputSchema
        self.error = error
        self.abortSignal = abortSignal
    }
}

/// Attempts to repair a tool call that failed to parse; returns `nil` when no repair is possible.
public typealias ToolCallRepairFunction = @Sendable (ToolCallRepairOptions) async throws -> LanguageModelV4ToolCall?
