import Foundation

/**
 A tool contains the description and the schema of the input that the tool expects.
 This enables the language model to generate the input.

 The tool can also contain an optional execute function for the actual execution function of the tool.

 Port of `@ai-sdk/provider-utils/types/tool.ts`.

 Uses `ModelMessage` from `ProviderUtils/ModelMessage.swift` for callback signatures.

 **Upstream reference**: `@ai-sdk/provider-utils/types/tool.ts`
 */

public struct Tool: Sendable {
    /// An optional description of what the tool does.
    /// Will be used by the language model to decide whether to use the tool.
    /// Not used for provider-defined tools.
    public let description: String?

    /// Additional provider-specific metadata.
    public let providerOptions: [String: JSONValue]?

    /// The schema of the input that the tool expects.
    public let inputSchema: FlexibleSchema<JSONValue>

    /// Whether the tool needs approval before it can be executed.
    public let needsApproval: NeedsApproval?

    /// Optional function that is called when the argument streaming starts.
    /// Only called when the tool is used in a streaming context.
    public let onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)?

    /// Optional function that is called when an argument streaming delta is available.
    /// Only called when the tool is used in a streaming context.
    public let onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?

    /// Optional function that is called when a tool call can be started.
    public let onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?

    /// Async function that is called with the arguments from the tool call and produces a result.
    public let execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> JSONValue)?

    /// Optional output schema for validation.
    public let outputSchema: FlexibleSchema<JSONValue>?

    /// Optional conversion function that maps the tool result to an output for the language model.
    public let toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?

    /// The type of the tool.
    public let type: ToolType?

    /// For provider-defined tools: the ID (format: "<provider>.<tool-name>")
    public let id: String?

    /// For provider-defined tools: the name
    public let name: String?

    /// For provider-defined tools: the arguments
    public let args: [String: JSONValue]?

    public init(
        description: String? = nil,
        providerOptions: [String: JSONValue]? = nil,
        inputSchema: FlexibleSchema<JSONValue>,
        needsApproval: NeedsApproval? = nil,
        onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
        onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
        onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
        execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> JSONValue)? = nil,
        outputSchema: FlexibleSchema<JSONValue>? = nil,
        toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? = nil,
        type: ToolType? = nil,
        id: String? = nil,
        name: String? = nil,
        args: [String: JSONValue]? = nil
    ) {
        self.description = description
        self.providerOptions = providerOptions
        self.inputSchema = inputSchema
        self.needsApproval = needsApproval
        self.onInputStart = onInputStart
        self.onInputDelta = onInputDelta
        self.onInputAvailable = onInputAvailable
        self.execute = execute
        self.outputSchema = outputSchema
        self.toModelOutput = toModelOutput
        self.type = type
        self.id = id
        self.name = name
        self.args = args
    }
}

/// The type of tool.
public enum ToolType: String, Sendable {
    /// Tool with user-defined input and output schemas.
    case function = "function"

    /// Tool that is defined at runtime (e.g. an MCP tool).
    case dynamic = "dynamic"

    /// Tool with provider-defined input and output schemas.
    case providerDefined = "provider-defined"
}

/**
 Whether the tool needs approval before it can be executed.

 ## TypeScript Mapping

 In TypeScript, the upstream type is:
 ```typescript
 needsApproval?: boolean | ((input, options) => boolean | Promise<boolean>)
 ```

 Swift adaptation using enum for better type safety:
 - TypeScript `true` → Swift `.always`
 - TypeScript `false` → Swift `.never`
 - TypeScript `function` → Swift `.conditional(function)`

 ## Usage Examples

 ```swift
 // Static approval (TypeScript: needsApproval: true)
 let tool1 = tool(
     inputSchema: schema,
     needsApproval: .always
 )

 // No approval (TypeScript: needsApproval: false)
 let tool2 = tool(
     inputSchema: schema,
     needsApproval: .never
 )

 // Dynamic approval (TypeScript: needsApproval: async (input, options) => {...})
 let tool3 = tool(
     inputSchema: schema,
     needsApproval: .conditional { input, options in
         // Check if input contains sensitive data
         guard case .object(let obj) = input,
               case .bool(let sensitive) = obj["sensitive"] else {
             return false
         }
         return sensitive
     }
 )
 ```

 ## Rationale

 Using an enum instead of `Bool | Closure` provides:
 - **Type safety**: Compiler enforces correct usage
 - **Pattern matching**: Easy to handle all cases exhaustively
 - **Clarity**: Intent is explicit (`.always` vs `true`)
 */
public enum NeedsApproval: Sendable {
    /// Always needs approval before execution.
    ///
    /// TypeScript equivalent: `needsApproval: true`
    case always

    /// Never needs approval, executes immediately.
    ///
    /// TypeScript equivalent: `needsApproval: false` or `needsApproval: undefined`
    case never

    /// Conditional approval based on input and execution context.
    ///
    /// The closure receives the tool input and approval options, and returns
    /// whether approval is needed for this specific invocation.
    ///
    /// TypeScript equivalent:
    /// ```typescript
    /// needsApproval: async (input, options) => boolean
    /// ```
    ///
    /// - Parameters:
    ///   - input: The tool input (JSONValue)
    ///   - options: Approval context (tool call ID, messages, experimental context)
    /// - Returns: `true` if approval is needed, `false` otherwise
    case conditional(@Sendable (JSONValue, ToolCallApprovalOptions) async throws -> Bool)
}

/// Additional options that are sent into each tool call.
public struct ToolCallOptions: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String

    /// Messages that were sent to the language model.
    /// The messages do not include the system prompt nor the assistant response that contained the tool call.
    public let messages: [ModelMessage]

    /// An optional abort signal closure.
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional context (experimental).
    public let experimentalContext: JSONValue?

    public init(
        toolCallId: String,
        messages: [ModelMessage],
        abortSignal: (@Sendable () -> Bool)? = nil,
        experimentalContext: JSONValue? = nil
    ) {
        self.toolCallId = toolCallId
        self.messages = messages
        self.abortSignal = abortSignal
        self.experimentalContext = experimentalContext
    }
}

/// Options for tool call delta (streaming).
public struct ToolCallDeltaOptions: Sendable {
    /// The input text delta.
    public let inputTextDelta: String

    /// The ID of the tool call.
    public let toolCallId: String

    /// Messages that were sent to the language model.
    public let messages: [ModelMessage]

    /// An optional abort signal closure.
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional context (experimental).
    public let experimentalContext: JSONValue?

    public init(
        inputTextDelta: String,
        toolCallId: String,
        messages: [ModelMessage],
        abortSignal: (@Sendable () -> Bool)? = nil,
        experimentalContext: JSONValue? = nil
    ) {
        self.inputTextDelta = inputTextDelta
        self.toolCallId = toolCallId
        self.messages = messages
        self.abortSignal = abortSignal
        self.experimentalContext = experimentalContext
    }
}

/// Options for tool call when input is available.
public struct ToolCallInputOptions: Sendable {
    /// The input for the tool call.
    public let input: JSONValue

    /// The ID of the tool call.
    public let toolCallId: String

    /// Messages that were sent to the language model.
    public let messages: [ModelMessage]

    /// An optional abort signal closure.
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional context (experimental).
    public let experimentalContext: JSONValue?

    public init(
        input: JSONValue,
        toolCallId: String,
        messages: [ModelMessage],
        abortSignal: (@Sendable () -> Bool)? = nil,
        experimentalContext: JSONValue? = nil
    ) {
        self.input = input
        self.toolCallId = toolCallId
        self.messages = messages
        self.abortSignal = abortSignal
        self.experimentalContext = experimentalContext
    }
}

/// Options for tool approval.
public struct ToolCallApprovalOptions: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String

    /// Messages that were sent to the language model.
    public let messages: [ModelMessage]

    /// Additional context (experimental).
    public let experimentalContext: JSONValue?

    public init(
        toolCallId: String,
        messages: [ModelMessage],
        experimentalContext: JSONValue? = nil
    ) {
        self.toolCallId = toolCallId
        self.messages = messages
        self.experimentalContext = experimentalContext
    }
}

/**
 Helper function for creating a tool with the specified configuration.

 Port of `@ai-sdk/provider-utils` `tool()` helper function.
 */
public func tool(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<JSONValue>,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> JSONValue)? = nil,
    outputSchema: FlexibleSchema<JSONValue>? = nil,
    toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? = nil
) -> Tool {
    Tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: inputSchema,
        needsApproval: needsApproval,
        onInputStart: onInputStart,
        onInputDelta: onInputDelta,
        onInputAvailable: onInputAvailable,
        execute: execute,
        outputSchema: outputSchema,
        toModelOutput: toModelOutput,
        type: nil  // nil means 'function' type
    )
}

/**
 Helper function for defining a dynamic tool.

 Port of `@ai-sdk/provider-utils` `dynamicTool()` helper function.
 */
public func dynamicTool(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<JSONValue>,
    execute: @escaping @Sendable (JSONValue, ToolCallOptions) async throws -> JSONValue,
    toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? = nil
) -> Tool {
    Tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: inputSchema,
        execute: execute,
        toModelOutput: toModelOutput,
        type: .dynamic
    )
}
