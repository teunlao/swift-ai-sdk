import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Parameters of one agent call.

 Port of `AgentCallParameters` from `@ai-sdk/ai/src/agent/agent.ts`. Pass
 either `prompt` or `messages`.
 */
public struct AgentCallParameters<CallOptions: Sendable>: Sendable {
    /// Options validated by the agent's `callOptionsSchema` and passed to `prepareCall`.
    public var options: CallOptions?

    /// A text prompt or a list of messages.
    public var prompt: PromptContent?

    /// A list of messages.
    public var messages: [ModelMessage]?

    public var abortSignal: (@Sendable () -> Bool)?

    /// Overrides the agent's timeout. First-chunk and chunk timeouts apply to streaming calls only.
    public var timeout: TimeoutConfiguration?

    public var onStart: GenerateTextOnStartCallback?
    public var onStepStart: GenerateTextOnStepStartCallback?
    public var onToolExecutionStart: OnToolExecutionStartCallback?
    public var onToolExecutionEnd: OnToolExecutionEndCallback?
    public var onStepEnd: GenerateTextOnStepEndCallback?
    public var onEnd: GenerateTextOnEndCallback?

    public init(
        options: CallOptions? = nil,
        prompt: PromptContent? = nil,
        messages: [ModelMessage]? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        timeout: TimeoutConfiguration? = nil,
        onStart: GenerateTextOnStartCallback? = nil,
        onStepStart: GenerateTextOnStepStartCallback? = nil,
        onToolExecutionStart: OnToolExecutionStartCallback? = nil,
        onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
        onStepEnd: GenerateTextOnStepEndCallback? = nil,
        onEnd: GenerateTextOnEndCallback? = nil
    ) {
        self.options = options
        self.prompt = prompt
        self.messages = messages
        self.abortSignal = abortSignal
        self.timeout = timeout
        self.onStart = onStart
        self.onStepStart = onStepStart
        self.onToolExecutionStart = onToolExecutionStart
        self.onToolExecutionEnd = onToolExecutionEnd
        self.onStepEnd = onStepEnd
        self.onEnd = onEnd
    }
}

/**
 Parameters of one streaming agent call.

 Port of `AgentStreamParameters` from `@ai-sdk/ai/src/agent/agent.ts`.
 */
public struct AgentStreamParameters<CallOptions: Sendable>: Sendable {
    public var call: AgentCallParameters<CallOptions>

    /// Stream transforms, applied in order.
    public var transform: [StreamTextTransform]

    public init(_ call: AgentCallParameters<CallOptions>, transform: [StreamTextTransform] = []) {
        self.call = call
        self.transform = transform
    }
}

/**
 An agent receives a prompt (text or messages) and generates or streams an
 output that consists of steps, tool calls, data parts, etc.

 Port of the `Agent` interface from `@ai-sdk/ai/src/agent/agent.ts`. Implement
 it for a custom agent, or use `ToolLoopAgent`.
 */
public protocol Agent: Sendable {
    associatedtype CallOptions: Sendable
    associatedtype OutputValue: Sendable
    associatedtype PartialOutput: Sendable

    /// The specification version of the agent interface (`agent-v1`).
    var version: String { get }

    var id: String? { get }

    var tools: ToolSet? { get }

    /// Generates an output (non-streaming).
    func generate(_ parameters: AgentCallParameters<CallOptions>) async throws -> DefaultGenerateTextResult<OutputValue>

    /// Streams an output.
    func stream(_ parameters: AgentStreamParameters<CallOptions>) async throws -> DefaultStreamTextResult<OutputValue, PartialOutput>
}

public extension Agent {
    /// Generates an output from a text prompt.
    func generate(
        prompt: String,
        options: CallOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        timeout: TimeoutConfiguration? = nil
    ) async throws -> DefaultGenerateTextResult<OutputValue> {
        try await generate(AgentCallParameters(
            options: options, prompt: .text(prompt), abortSignal: abortSignal, timeout: timeout
        ))
    }

    /// Generates an output from messages.
    func generate(
        messages: [ModelMessage],
        options: CallOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        timeout: TimeoutConfiguration? = nil
    ) async throws -> DefaultGenerateTextResult<OutputValue> {
        try await generate(AgentCallParameters(
            options: options, messages: messages, abortSignal: abortSignal, timeout: timeout
        ))
    }

    /// Streams an output from a text prompt.
    func stream(
        prompt: String,
        options: CallOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        timeout: TimeoutConfiguration? = nil,
        transform: [StreamTextTransform] = []
    ) async throws -> DefaultStreamTextResult<OutputValue, PartialOutput> {
        try await stream(AgentStreamParameters(
            AgentCallParameters(options: options, prompt: .text(prompt), abortSignal: abortSignal, timeout: timeout),
            transform: transform
        ))
    }

    /// Streams an output from messages.
    func stream(
        messages: [ModelMessage],
        options: CallOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        timeout: TimeoutConfiguration? = nil,
        transform: [StreamTextTransform] = []
    ) async throws -> DefaultStreamTextResult<OutputValue, PartialOutput> {
        try await stream(AgentStreamParameters(
            AgentCallParameters(options: options, messages: messages, abortSignal: abortSignal, timeout: timeout),
            transform: transform
        ))
    }
}

/**
 Creates a callback that invokes the callbacks concurrently, ignoring their errors.

 Port of `@ai-sdk/ai/src/util/merge-callbacks.ts`.
 */
func mergeCallbacks<Event: Sendable>(
    _ callbacks: (@Sendable (Event) async throws -> Void)?...
) -> @Sendable (Event) async throws -> Void {
    let callbacks = callbacks.compactMap { $0 }
    return { event in
        await withTaskGroup(of: Void.self) { group in
            for callback in callbacks {
                group.addTask { try? await callback(event) }
            }
        }
    }
}
