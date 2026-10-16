import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 An agent that runs tools in a loop. In each step it calls the model; when the
 model calls tools, it executes them and calls the model again with the results.

 Port of `@ai-sdk/ai/src/agent/tool-loop-agent.ts`. The loop continues until:
 - the model finishes with a reason other than tool calls, or
 - a called tool has no `execute` function, or
 - a tool call needs approval, or
 - a stop condition is met (default: 20 steps).
 */
public final class ToolLoopAgent<CallOptions: Sendable, OutputValue: Sendable, PartialOutput: Sendable>: Agent, Sendable {
    public let version = "agent-v1"

    private let settings: ToolLoopAgentSettings<CallOptions, OutputValue, PartialOutput>

    public init(_ settings: ToolLoopAgentSettings<CallOptions, OutputValue, PartialOutput>) {
        self.settings = settings
    }

    @available(*, deprecated, renamed: "init(_:)")
    public convenience init(settings: ToolLoopAgentSettings<CallOptions, OutputValue, PartialOutput>) {
        self.init(settings)
    }

    public var id: String? { settings.id }

    public var tools: ToolSet? { settings.tools }

    private func prepareCall(_ parameters: AgentCallParameters<CallOptions>) async throws -> ToolLoopAgentCall<CallOptions> {
        var options = parameters.options
        if let schema = settings.callOptionsSchema, let value = options {
            options = try await validateTypes(ValidateTypesOptions(
                value: value,
                schema: schema,
                context: TypeValidationContext(field: "options")
            ))
        }

        let baseCall = ToolLoopAgentCall(
            options: options,
            prompt: parameters.prompt,
            messages: parameters.messages,
            instructions: settings.instructions,
            allowSystemInMessages: settings.allowSystemInMessages,
            model: settings.model,
            tools: settings.tools,
            toolChoice: settings.toolChoice,
            stopWhen: settings.stopWhen ?? [createDefaultStopCondition(stepCount: 20)],
            telemetry: settings.telemetry,
            activeTools: settings.activeTools,
            toolOrder: settings.toolOrder,
            toolCallConcurrency: settings.toolCallConcurrency,
            toolApproval: settings.toolApproval,
            prepareStep: settings.prepareStep,
            repairToolCall: settings.repairToolCall,
            refineToolInput: settings.refineToolInput,
            providerOptions: settings.providerOptions,
            download: settings.download,
            include: settings.include,
            runtimeContext: settings.runtimeContext,
            toolsContext: settings.toolsContext,
            internalOptions: settings.internalOptions,
            callSettings: settings.callSettings
        )

        let preparedCall = try await settings.prepareCall?(baseCall) ?? baseCall

        // Rejects a prompt given both as `prompt` and `messages` before the call starts.
        _ = try standardizePrompt(Prompt(
            instructions: preparedCall.instructions,
            allowSystemInMessages: preparedCall.allowSystemInMessages,
            prompt: preparedCall.prompt,
            messages: preparedCall.messages
        ))
        return preparedCall
    }

    /// Settings for the model call, tagged so usage can be attributed to `ToolLoopAgent`.
    private func callSettings(
        _ preparedCall: ToolLoopAgentCall<CallOptions>,
        parameters: AgentCallParameters<CallOptions>
    ) -> CallSettings {
        var callSettings = preparedCall.callSettings
        callSettings.abortSignal = parameters.abortSignal
        callSettings.timeout = parameters.timeout ?? preparedCall.callSettings.timeout
        callSettings.headers = withUserAgentSuffix(callSettings.headers ?? [:], "ai-sdk-agent/tool-loop")
        return callSettings
    }

    public func generate(_ parameters: AgentCallParameters<CallOptions>) async throws -> DefaultGenerateTextResult<OutputValue> {
        let preparedCall = try await prepareCall(parameters)
        let (prompt, messages) = preparedCall.promptArguments

        return try await generateText(
            model: preparedCall.model,
            tools: preparedCall.tools,
            toolChoice: preparedCall.toolChoice,
            instructions: preparedCall.instructions,
            prompt: prompt,
            messages: messages,
            allowSystemInMessages: preparedCall.allowSystemInMessages,
            stopWhen: preparedCall.stopWhen,
            output: settings.output,
            toolApproval: preparedCall.toolApproval,
            telemetry: preparedCall.telemetry,
            providerOptions: preparedCall.providerOptions,
            activeTools: preparedCall.activeTools,
            toolOrder: preparedCall.toolOrder,
            toolCallConcurrency: preparedCall.toolCallConcurrency,
            prepareStep: preparedCall.prepareStep,
            repairToolCall: preparedCall.repairToolCall,
            refineToolInput: preparedCall.refineToolInput,
            download: preparedCall.download,
            runtimeContext: preparedCall.runtimeContext ?? [:],
            toolsContext: preparedCall.toolsContext,
            include: preparedCall.include?.generateTextInclude,
            internalOptions: GenerateTextInternalOptions(
                generateId: preparedCall.internalOptions?.generateId,
                generateCallId: preparedCall.internalOptions?.generateCallId
            ),
            onStart: mergeCallbacks(settings.onStart, parameters.onStart),
            onStepStart: mergeCallbacks(settings.onStepStart, parameters.onStepStart),
            onLanguageModelCallStart: settings.onLanguageModelCallStart,
            onLanguageModelCallEnd: settings.onLanguageModelCallEnd,
            onToolExecutionStart: mergeCallbacks(settings.onToolExecutionStart, parameters.onToolExecutionStart),
            onToolExecutionEnd: mergeCallbacks(settings.onToolExecutionEnd, parameters.onToolExecutionEnd),
            onStepEnd: mergeCallbacks(settings.onStepEnd, parameters.onStepEnd),
            onEnd: mergeCallbacks(settings.onEnd, parameters.onEnd),
            settings: callSettings(preparedCall, parameters: parameters)
        )
    }

    public func stream(_ parameters: AgentStreamParameters<CallOptions>) async throws -> DefaultStreamTextResult<OutputValue, PartialOutput> {
        let call = parameters.call
        let preparedCall = try await prepareCall(call)
        let (prompt, messages) = preparedCall.promptArguments
        let onEnd = mergeCallbacks(settings.onEnd, call.onEnd)

        return try streamText(
            model: preparedCall.model,
            tools: preparedCall.tools,
            toolChoice: preparedCall.toolChoice,
            instructions: preparedCall.instructions,
            prompt: prompt,
            messages: messages,
            allowSystemInMessages: preparedCall.allowSystemInMessages,
            stopWhen: preparedCall.stopWhen,
            output: settings.output,
            toolApproval: preparedCall.toolApproval,
            telemetry: preparedCall.telemetry,
            providerOptions: preparedCall.providerOptions,
            activeTools: preparedCall.activeTools,
            toolOrder: preparedCall.toolOrder,
            toolCallConcurrency: preparedCall.toolCallConcurrency,
            prepareStep: preparedCall.prepareStep,
            repairToolCall: preparedCall.repairToolCall,
            refineToolInput: preparedCall.refineToolInput,
            transform: parameters.transform,
            download: preparedCall.download,
            runtimeContext: preparedCall.runtimeContext ?? [:],
            toolsContext: preparedCall.toolsContext,
            include: preparedCall.include?.streamTextInclude,
            internalOptions: StreamTextInternalOptions(
                generateId: preparedCall.internalOptions?.generateId,
                generateCallId: preparedCall.internalOptions?.generateCallId
            ),
            onEnd: { try await onEnd($0.event) },
            onStepEnd: mergeCallbacks(settings.onStepEnd, call.onStepEnd),
            onStart: mergeCallbacks(settings.onStart, call.onStart),
            onStepStart: mergeCallbacks(settings.onStepStart, call.onStepStart),
            onLanguageModelCallStart: settings.onLanguageModelCallStart,
            onLanguageModelCallEnd: settings.onLanguageModelCallEnd,
            onToolExecutionStart: mergeCallbacks(settings.onToolExecutionStart, call.onToolExecutionStart),
            onToolExecutionEnd: mergeCallbacks(settings.onToolExecutionEnd, call.onToolExecutionEnd),
            settings: callSettings(preparedCall, parameters: call)
        )
    }

    /// Converts UI messages to model messages and streams the agent output as a UI message stream response.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public func respond<Message: UIMessageConvertible>(
        messages: [Message],
        ignoreIncompleteToolCalls: Bool = false,
        options: StreamTextUIResponseOptions<Message>? = nil
    ) async throws -> UIMessageStreamResponse<Message> {
        let modelMessages = try convertToModelMessages(
            messages: messages,
            options: ConvertToModelMessagesOptions(
                tools: settings.tools,
                ignoreIncompleteToolCalls: ignoreIncompleteToolCalls
            )
        )
        let result = try await stream(messages: modelMessages)
        return result.toUIMessageStreamResponse(options: options)
    }
}

extension ToolLoopAgentCall {
    /// The prompt as `generateText` and `streamText` take it.
    var promptArguments: (prompt: String?, messages: [ModelMessage]?) {
        switch prompt {
        case .text(let text): return (text, messages)
        case .messages(let promptMessages): return (nil, promptMessages)
        case nil: return (nil, messages)
        }
    }
}

/**
 Stops the loop at `stepCount` steps and warns that the default limit was reached.

 Port of `@ai-sdk/ai/src/agent/default-stop-condition.ts`. Stop conditions are
 only evaluated when the loop could continue, so a call that finishes
 naturally at the limit logs nothing.
 */
func createDefaultStopCondition(stepCount: Int) -> StopCondition {
    { steps in
        guard steps.count == stepCount else { return false }
        logWarnings([.languageModel(.other(message:
            "The tool loop stopped because it reached the default stopWhen condition, isStepCount(\(stepCount)). "
                + "To allow more steps, set stopWhen to isStepCount(...) with a higher limit or provide a custom stop condition. "
                + "Learn more: https://ai-sdk.dev/docs/agents/loop-control"
        ))])
        return true
    }
}

@available(*, deprecated, renamed: "ToolLoopAgent")
public typealias Experimental_Agent<OutputValue: Sendable, PartialOutput: Sendable> = ToolLoopAgent<Never, OutputValue, PartialOutput>

/// An agent with text output and no call options.
public typealias BasicAgent = ToolLoopAgent<Never, String, String>
