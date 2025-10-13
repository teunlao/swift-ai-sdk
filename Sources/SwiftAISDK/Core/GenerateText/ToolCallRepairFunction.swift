import Foundation

/**
 A function that attempts to repair a tool call that failed to parse.

 It receives the error and the context as arguments and returns the repair
 tool call or nil if the repair is not possible.

 Port of `@ai-sdk/ai/src/generate-text/tool-call-repair-function.ts`.
 */

/// Options for tool call repair function.
public struct ToolCallRepairOptions: Sendable {
    /// The system prompt.
    public let system: String?

    /// The messages in the current generation step.
    public let messages: [ModelMessage]

    /// The tool call that failed to parse.
    public let toolCall: LanguageModelV3ToolCall

    /// The tools that are available.
    public let tools: ToolSet

    /// A function that returns the JSON Schema for a tool.
    public let inputSchema: @Sendable (String) async throws -> [String: JSONValue]

    /// The error that occurred while parsing the tool call.
    public let error: any Error

    public init(
        system: String?,
        messages: [ModelMessage],
        toolCall: LanguageModelV3ToolCall,
        tools: ToolSet,
        inputSchema: @Sendable @escaping (String) async throws -> [String: JSONValue],
        error: any Error
    ) {
        self.system = system
        self.messages = messages
        self.toolCall = toolCall
        self.tools = tools
        self.inputSchema = inputSchema
        self.error = error
    }
}

/// A function that attempts to repair a tool call that failed to parse.
public typealias ToolCallRepairFunction = @Sendable (ToolCallRepairOptions) async throws -> LanguageModelV3ToolCall?
