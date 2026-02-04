import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 High-level helper that encapsulates language model configuration, tool usage,
 and multi-step orchestration. Mirrors `@ai-sdk/ai/src/agent/agent.ts`.
 */
public final class Agent<OutputValue: Sendable, PartialOutputValue: Sendable>: @unchecked Sendable {
    public typealias Settings = AgentSettings<OutputValue, PartialOutputValue>

    private let settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    // MARK: - Configuration accessors

    /// The configured agent name.
    public var name: String? { settings.name }

    /// Tools available to the agent.
    public var tools: ToolSet? { settings.tools }

    // MARK: - Generation APIs

    /// Runs a non-streaming generation with the agent configuration.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public func generate(prompt options: Prompt) async throws -> DefaultGenerateTextResult<OutputValue> {
        let mergedPrompt = try mergePrompt(options)
        let stopConditions = settings.stopWhen ?? [stepCountIs(20)]

        if let promptContent = mergedPrompt.prompt {
            switch promptContent {
            case .text(let text):
                return try await generateText(
                    model: settings.model,
                    tools: settings.tools,
                    toolChoice: settings.toolChoice,
                    system: mergedPrompt.system,
                    prompt: text,
                    messages: nil,
                    stopWhen: stopConditions,
                    experimentalOutput: adaptOutputForGenerate(settings.experimentalOutput),
                    experimentalTelemetry: settings.experimentalTelemetry,
                    providerOptions: settings.providerOptions,
                    experimentalActiveTools: nil,
                    activeTools: settings.activeTools,
                    experimentalPrepareStep: settings.experimentalPrepareStep,
                    prepareStep: settings.prepareStep,
                    experimentalRepairToolCall: settings.experimentalRepairToolCall,
                    experimentalDownload: nil,
                    experimentalContext: settings.experimentalContext,
                    internalOptions: GenerateTextInternalOptions(),
                    onStepFinish: settings.onStepFinish,
                    onFinish: settings.onFinish,
                    settings: settings.callSettings
                )
            case .messages(let messages):
                return try await generateText(
                    model: settings.model,
                    tools: settings.tools,
                    toolChoice: settings.toolChoice,
                    system: mergedPrompt.system,
                    prompt: nil,
                    messages: messages,
                    stopWhen: stopConditions,
                    experimentalOutput: adaptOutputForGenerate(settings.experimentalOutput),
                    experimentalTelemetry: settings.experimentalTelemetry,
                    providerOptions: settings.providerOptions,
                    experimentalActiveTools: nil,
                    activeTools: settings.activeTools,
                    experimentalPrepareStep: settings.experimentalPrepareStep,
                    prepareStep: settings.prepareStep,
                    experimentalRepairToolCall: settings.experimentalRepairToolCall,
                    experimentalDownload: nil,
                    experimentalContext: settings.experimentalContext,
                    internalOptions: GenerateTextInternalOptions(),
                    onStepFinish: settings.onStepFinish,
                    onFinish: settings.onFinish,
                    settings: settings.callSettings
                )
            }
        }

        if let messages = mergedPrompt.messages {
            return try await generateText(
                model: settings.model,
                tools: settings.tools,
                toolChoice: settings.toolChoice,
                system: mergedPrompt.system,
                prompt: nil,
                messages: messages,
                stopWhen: stopConditions,
                experimentalOutput: adaptOutputForGenerate(settings.experimentalOutput),
                experimentalTelemetry: settings.experimentalTelemetry,
                providerOptions: settings.providerOptions,
                experimentalActiveTools: nil,
                activeTools: settings.activeTools,
                experimentalPrepareStep: settings.experimentalPrepareStep,
                prepareStep: settings.prepareStep,
                experimentalRepairToolCall: settings.experimentalRepairToolCall,
                experimentalDownload: nil,
                experimentalContext: settings.experimentalContext,
                internalOptions: GenerateTextInternalOptions(),
                onStepFinish: settings.onStepFinish,
                onFinish: settings.onFinish,
                settings: settings.callSettings
            )
        }

        let systemDescription = mergedPrompt.system ?? "nil"
        throw InvalidPromptError(
            prompt: "Prompt(system: \(systemDescription))",
            message: "Agent requires either prompt text or messages."
        )
    }

    /// Starts a streaming generation with the agent configuration.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public func stream(prompt options: Prompt) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
        let mergedPrompt = try mergePrompt(options)
        let standardizedPrompt = try standardizePrompt(mergedPrompt)
        let stopConditions = settings.stopWhen ?? [stepCountIs(20)]

        let result = try streamText(
            model: settings.model,
            system: standardizedPrompt.system,
            messages: standardizedPrompt.messages,
            tools: settings.tools,
            toolChoice: settings.toolChoice,
            providerOptions: settings.providerOptions,
            experimentalActiveTools: nil,
            activeTools: settings.activeTools,
            experimentalOutput: settings.experimentalOutput,
            experimentalTelemetry: settings.experimentalTelemetry,
            experimentalApprove: nil,
            experimentalTransform: [],
            experimentalDownload: nil,
            experimentalRepairToolCall: settings.experimentalRepairToolCall,
            experimentalContext: settings.experimentalContext,
            includeRawChunks: false,
            stopWhen: stopConditions,
            onChunk: nil,
            onStepFinish: makeStreamOnStepFinish(),
            onFinish: makeStreamOnFinish(),
            onAbort: nil,
            onError: nil,
            internalOptions: StreamTextInternalOptions(),
            settings: settings.callSettings
        )
        return result
    }

    /// Creates a UI message stream response by converting UI chat messages to model messages
    /// and streaming the agent output back to the client.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public func respond<Message: UIMessageConvertible>(
        messages: [Message],
        ignoreIncompleteToolCalls: Bool = false,
        options: StreamTextUIResponseOptions<Message>? = nil
    ) throws -> UIMessageStreamResponse<Message> {
        let modelMessages = try convertToModelMessages(
            messages: messages,
            options: ConvertToModelMessagesOptions(
                tools: settings.tools,
                ignoreIncompleteToolCalls: ignoreIncompleteToolCalls
            )
        )

        let streamResult = try stream(prompt: Prompt(messages: modelMessages))
        return streamResult.toUIMessageStreamResponse(options: options)
    }

    // MARK: - Helpers

    private func mergePrompt(_ options: Prompt) throws -> Prompt {
        let system = options.system ?? settings.system

        if let promptContent = options.prompt {
            switch promptContent {
            case .text(let text):
                return Prompt(system: system, prompt: .text(text))
            case .messages(let messages):
                return Prompt(system: system, messages: messages)
            }
        }

        if let messages = options.messages {
            return Prompt(system: system, messages: messages)
        }

        let systemDescription = system ?? "nil"
        throw InvalidPromptError(
            prompt: "Prompt(system: \(systemDescription))",
            message: "Agent requires either prompt text or messages."
        )
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    private func makeStreamOnStepFinish() -> StreamTextOnStepFinish? {
        guard let callback = settings.onStepFinish else { return nil }
        return { step in
            Task {
                do {
                    try await callback(step)
                } catch {
                    // Suppress callback failures to keep streaming alive.
                }
            }
        }
    }

    private func adaptOutputForGenerate(
        _ specification: Output.Specification<OutputValue, PartialOutputValue>?
    ) -> Output.Specification<OutputValue, JSONValue>? {
        guard let specification else { return nil }
        return Output.Specification<OutputValue, JSONValue>(
            type: specification.type,
            responseFormat: { try await specification.responseFormat() },
            parsePartial: { _ in nil },
            parseOutput: { text, context in
                try await specification.parseOutput(text: text, context: context)
            }
        )
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    private func makeStreamOnFinish() -> StreamTextOnFinish? {
        guard let callback = settings.onFinish else { return nil }
        return { finalStep, steps, totalUsage, finishReason in
            Task {
                let event = GenerateTextFinishEvent(
                    finishReason: finishReason,
                    rawFinishReason: finalStep.rawFinishReason,
                    usage: finalStep.usage,
                    content: finalStep.content,
                    text: finalStep.text,
                    reasoningText: finalStep.reasoningText,
                    reasoning: finalStep.reasoning,
                    files: finalStep.files,
                    sources: finalStep.sources,
                    toolCalls: finalStep.toolCalls,
                    staticToolCalls: finalStep.staticToolCalls,
                    dynamicToolCalls: finalStep.dynamicToolCalls,
                    toolResults: finalStep.toolResults,
                    staticToolResults: finalStep.staticToolResults,
                    dynamicToolResults: finalStep.dynamicToolResults,
                    request: finalStep.request,
                    response: finalStep.response,
                    warnings: finalStep.warnings,
                    providerMetadata: finalStep.providerMetadata,
                    steps: steps,
                    totalUsage: totalUsage
                )

                do {
                    try await callback(event)
                } catch {
                    // Suppress callback failures to keep streaming alive.
                }
            }
        }
    }
}

/// Convenience alias for the most common agent type (no structured outputs).
public typealias BasicAgent = Agent<Never, Never>

// MARK: - Deprecated aliases

@available(*, deprecated, renamed: "Agent")
public typealias Experimental_Agent<OutputValue: Sendable, PartialOutputValue: Sendable> = Agent<OutputValue, PartialOutputValue>
