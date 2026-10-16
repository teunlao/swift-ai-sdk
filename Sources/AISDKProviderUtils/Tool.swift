import Foundation
import AISDKProvider

/**
 Represents the possible result kinds from a tool execution.

 Port of `@ai-sdk/provider-utils/src/types/tool.ts` - ToolExecuteFunction return type.

 TypeScript upstream returns `AsyncIterable<OUTPUT> | PromiseLike<OUTPUT> | OUTPUT`.
 Swift adaptation uses enum with three cases to represent this union type:
 - `.value`: Immediate synchronous result
 - `.future`: Deferred async computation (like Promise)
 - `.stream`: Streaming async sequence (like AsyncIterable)
 */
public enum ToolExecutionResult<Output: Sendable>: Sendable {
    /// Immediate synchronous value.
    case value(Output)

    /// Deferred async computation. The closure captures input/options and executes when needed.
    case future(@Sendable () async throws -> Output)

    /// Streaming async sequence.
    case stream(AsyncThrowingStream<Output, Error>)

    /// Check if the result is streaming.
    ///
    /// Port of `@ai-sdk/provider-utils/src/is-async-iterable.ts` check.
    public var isStreaming: Bool {
        if case .stream = self { return true }
        return false
    }

    /// Convert any result type to a unified AsyncThrowingStream.
    ///
    /// **Note**: AsyncThrowingStream is single-use (like JS AsyncIterable).
    /// Call this method at the consumption point, not for storage.
    public func asAsyncStream() -> AsyncThrowingStream<Output, Error> {
        switch self {
        case .value(let output):
            return AsyncThrowingStream { continuation in
                continuation.yield(output)
                continuation.finish()
            }

        case .future(let operation):
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let output = try await operation()
                        continuation.yield(output)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }

        case .stream(let stream):
            return stream
        }
    }

    /// Resolve to a single value (for non-streaming cases).
    ///
    /// - Throws: `ToolExecutionResultError.streamingResultRequiresStreamConsumption`
    ///   if called on a `.stream` case.
    public func resolve() async throws -> Output {
        switch self {
        case .value(let output):
            return output
        case .future(let operation):
            return try await operation()
        case .stream:
            throw ToolExecutionResultError.streamingResultRequiresStreamConsumption
        }
    }
}

/**
 Errors related to tool execution results.
 */
public enum ToolExecutionResultError: Error, LocalizedError {
    /// Attempted to resolve a streaming result without consuming its stream.
    case streamingResultRequiresStreamConsumption

    public var errorDescription: String? {
        switch self {
        case .streamingResultRequiresStreamConsumption:
            return "Attempted to resolve a streaming tool result without consuming its stream."
        }
    }
}

/**
 A context object that is passed into tool execution.

 Port of `@ai-sdk/provider-utils/src/types/context.ts`. Upstream allows any
 value (`Record<string, unknown>`); the Swift port keeps context JSON so it can
 be validated against a `contextSchema` and filtered for telemetry.
 */
public typealias Context = [String: JSONValue]

/**
 Output of a tool result that is sent to the language model.

 Port of `ToolResultOutput` from `@ai-sdk/provider-utils/src/types/content-part.ts`.
 */
public typealias ToolResultOutput = LanguageModelV3ToolResultOutput

/**
 Description of a function tool: fixed text, or text resolved per call from the
 tool context.

 Port of the `description` field of upstream `BaseFunctionTool`
 (`string | ((options: { context }) => string)`).
 */
public enum ToolDescription: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case text(String)
    case resolve(@Sendable (ToolDescriptionOptions) -> String)

    public init(stringLiteral value: String) {
        self = .text(value)
    }

    public init(stringInterpolation: DefaultStringInterpolation) {
        self = .text(String(stringInterpolation: stringInterpolation))
    }

    /// Resolves the description for the given tool context.
    public func resolve(context: Context?) -> String {
        switch self {
        case .text(let text):
            return text
        case .resolve(let resolver):
            return resolver(ToolDescriptionOptions(context: context))
        }
    }

    /// The fixed description text, or `nil` when the description is resolved per call.
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}

/// Options passed to a description resolver.
public struct ToolDescriptionOptions: Sendable {
    /// The tool context of the current call.
    public let context: Context?

    public init(context: Context?) {
        self.context = context
    }
}

/// Options passed to `Tool.toModelOutput`.
public struct ToolModelOutputOptions: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String

    /// The input of the tool call.
    public let input: JSONValue

    /// The output of the tool call.
    public let output: JSONValue

    public init(toolCallId: String, input: JSONValue, output: JSONValue) {
        self.toolCallId = toolCallId
        self.input = input
        self.output = output
    }
}

/**
 A tool contains the description and the schema of the input that the tool expects.
 This enables the language model to generate the input.

 The tool can also contain an optional execute function for the actual execution function of the tool.

 Port of `@ai-sdk/provider-utils/src/types/tool.ts`. The upstream union of
 function, dynamic, provider-defined and provider-executed tools is one struct
 discriminated by `type` (`nil` means `function`).
 */
public struct Tool: Sendable {
    /// Defers exposing the tool until it is discovered by tool search.
    /// Discovered tools become available on the next model step.
    public let deferLoading: Bool?

    /// Description of what the tool does: fixed text, or resolved per call from the tool context.
    /// Used by the language model to decide whether to use the tool. Not used for provider tools.
    public let description: ToolDescription?

    /// An optional title of the tool.
    @available(*, deprecated, message: "Use `metadata` for source-specific tool display metadata.")
    public var title: String? { _title }
    let _title: String?

    /// Additional provider-specific metadata, passed through to the provider.
    public let providerOptions: [String: JSONValue]?

    /// Optional metadata for the tool (used by some adapters like MCP).
    public let _meta: [String: JSONValue]?

    /// Metadata about the tool itself (e.g. its source). Not sent to the language model;
    /// propagated onto the resulting tool call's `toolMetadata`.
    public let metadata: [String: JSONValue]?

    /// The schema of the input that the tool expects.
    public let inputSchema: FlexibleSchema<JSONValue>

    /// An optional schema describing the context that the tool expects.
    /// The context is validated against it and passed to execution as `options.context`.
    public let contextSchema: FlexibleSchema<JSONValue>?

    /// An optional list of input examples that show the language model what the input should look like.
    public let inputExamples: [LanguageModelV3ToolInputExample]?

    /// Strict mode setting for the tool.
    public let strict: Bool?

    /// Whether the tool needs approval before it can be executed.
    ///
    /// Upstream deprecates this in favor of `toolApproval` on `generateText` / `streamText`.
    public let needsApproval: NeedsApproval?

    /// Called when the model starts generating the tool input.
    /// In non-streaming contexts, it is called immediately before `onInputAvailable`.
    public let onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)?

    /// Called when an argument streaming delta is available (streaming only).
    public let onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?

    /// Called when a tool call can be started, even if the execute function is not provided.
    public let onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?

    /// Called with the arguments from the tool call; produces a result.
    public let execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)?

    /// Optional output schema.
    public let outputSchema: FlexibleSchema<JSONValue>?

    /// Maps the tool result to an output for the language model.
    /// If not provided, the tool result is sent as JSON (or text for a string output).
    public let toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)?

    /// The type of the tool (`nil` means `function`).
    public let type: ToolType?

    /// For provider tools: the ID (format: "<provider>.<tool-name>").
    public let id: String?

    /// For provider tools: the name.
    public let name: String?

    /// For provider tools: the arguments.
    public let args: [String: JSONValue]?

    /// For provider tools: whether the provider executes the tool.
    public let isProviderExecuted: Bool?

    /// For provider-executed tools: whether the tool result may arrive in a later turn
    /// than the tool call.
    public let supportsDeferredResults: Bool?

    public init(
        deferLoading: Bool? = nil,
        description: ToolDescription? = nil,
        title: String? = nil,
        providerOptions: [String: JSONValue]? = nil,
        _meta: [String: JSONValue]? = nil,
        metadata: [String: JSONValue]? = nil,
        inputSchema: FlexibleSchema<JSONValue>,
        contextSchema: FlexibleSchema<JSONValue>? = nil,
        inputExamples: [LanguageModelV3ToolInputExample]? = nil,
        strict: Bool? = nil,
        needsApproval: NeedsApproval? = nil,
        onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
        onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
        onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
        execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
        outputSchema: FlexibleSchema<JSONValue>? = nil,
        toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)? = nil,
        type: ToolType? = nil,
        id: String? = nil,
        name: String? = nil,
        args: [String: JSONValue]? = nil,
        isProviderExecuted: Bool? = nil,
        supportsDeferredResults: Bool? = nil
    ) {
        self.deferLoading = deferLoading
        self.description = description
        self._title = title
        self.providerOptions = providerOptions
        self._meta = _meta
        self.metadata = metadata
        self.inputSchema = inputSchema
        self.contextSchema = contextSchema
        self.inputExamples = inputExamples
        self.strict = strict
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
        self.isProviderExecuted = isProviderExecuted
        self.supportsDeferredResults = supportsDeferredResults
    }
}

/// The type of tool.
public enum ToolType: String, Sendable {
    /// Tool with user-defined input and output schemas.
    case function = "function"

    /// Tool that is defined at runtime (e.g. an MCP tool).
    case dynamic = "dynamic"

    /// Tool with provider-defined input and output schemas.
    case provider = "provider"
}

/**
 Whether the tool needs approval before it can be executed.

 Port of upstream `needsApproval?: boolean | ToolNeedsApprovalFunction`:
 `true` → `.always`, `false` → `.never`, a function → `.conditional`.
 */
public enum NeedsApproval: Sendable {
    /// Always needs approval before execution.
    case always

    /// Never needs approval.
    case never

    /// Approval decided per call from the tool input and approval options.
    case conditional(@Sendable (JSONValue, ToolCallApprovalOptions) async throws -> Bool)
}

/**
 Additional options that are sent into each tool execution.

 Port of `ToolExecutionOptions` from `@ai-sdk/provider-utils/src/types/tool-execute-function.ts`.
 */
public struct ToolExecutionOptions: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String

    /// Messages that were sent to the language model to initiate the response that contained the tool call.
    /// The messages do not include the system prompt nor the assistant response that contained the tool call.
    public let messages: [ModelMessage]

    /// An optional abort signal that indicates that the overall operation should be aborted.
    public let abortSignal: (@Sendable () -> Bool)?

    /// Tool context as defined by the tool's context schema.
    /// Treat it as immutable; update context in `prepareStep` instead.
    public let context: Context?

    public init(
        toolCallId: String,
        messages: [ModelMessage],
        abortSignal: (@Sendable () -> Bool)? = nil,
        context: Context? = nil
    ) {
        self.toolCallId = toolCallId
        self.messages = messages
        self.abortSignal = abortSignal
        self.context = context
    }
}

@available(*, deprecated, renamed: "ToolExecutionOptions")
public typealias ToolCallOptions = ToolExecutionOptions

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

    /// Tool context as defined by the tool's context schema.
    public let context: Context?

    public init(
        inputTextDelta: String,
        toolCallId: String,
        messages: [ModelMessage],
        abortSignal: (@Sendable () -> Bool)? = nil,
        context: Context? = nil
    ) {
        self.inputTextDelta = inputTextDelta
        self.toolCallId = toolCallId
        self.messages = messages
        self.abortSignal = abortSignal
        self.context = context
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

    /// Tool context as defined by the tool's context schema.
    public let context: Context?

    public init(
        input: JSONValue,
        toolCallId: String,
        messages: [ModelMessage],
        abortSignal: (@Sendable () -> Bool)? = nil,
        context: Context? = nil
    ) {
        self.input = input
        self.toolCallId = toolCallId
        self.messages = messages
        self.abortSignal = abortSignal
        self.context = context
    }
}

/// Options for a tool's `needsApproval` function.
public struct ToolCallApprovalOptions: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String

    /// Messages that were sent to the language model.
    public let messages: [ModelMessage]

    /// Tool context as defined by the tool's context schema.
    public let context: Context?

    public init(
        toolCallId: String,
        messages: [ModelMessage],
        context: Context? = nil
    ) {
        self.toolCallId = toolCallId
        self.messages = messages
        self.context = context
    }
}

/**
 Helper function for creating a tool with the specified configuration.

 Port of `@ai-sdk/provider-utils` `tool()` helper function.
 */
public func tool(
    description: ToolDescription? = nil,
    title: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    _meta: [String: JSONValue]? = nil,
    metadata: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<JSONValue>,
    contextSchema: FlexibleSchema<JSONValue>? = nil,
    inputExamples: [LanguageModelV3ToolInputExample]? = nil,
    strict: Bool? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
    outputSchema: FlexibleSchema<JSONValue>? = nil,
    toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)? = nil,
    deferLoading: Bool? = nil
) -> Tool {
    Tool(
        deferLoading: deferLoading,
        description: description,
        title: title,
        providerOptions: providerOptions,
        _meta: _meta,
        metadata: metadata,
        inputSchema: inputSchema,
        contextSchema: contextSchema,
        inputExamples: inputExamples,
        strict: strict,
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
    description: ToolDescription? = nil,
    title: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    _meta: [String: JSONValue]? = nil,
    metadata: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<JSONValue>,
    contextSchema: FlexibleSchema<JSONValue>? = nil,
    strict: Bool? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: @escaping @Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>,
    toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)? = nil,
    deferLoading: Bool? = nil
) -> Tool {
    Tool(
        deferLoading: deferLoading,
        description: description,
        title: title,
        providerOptions: providerOptions,
        _meta: _meta,
        metadata: metadata,
        inputSchema: inputSchema,
        contextSchema: contextSchema,
        strict: strict,
        needsApproval: needsApproval,
        onInputStart: onInputStart,
        onInputDelta: onInputDelta,
        onInputAvailable: onInputAvailable,
        execute: execute,
        toModelOutput: toModelOutput,
        type: .dynamic
    )
}
