import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Event passed to `onLanguageModelCallStart` immediately before a provider call.

 Port of `LanguageModelCallStartEvent` from `@ai-sdk/ai/src/generate-text/language-model-events.ts`.
 Call options are reachable as members (`event.temperature`).
 */
@dynamicMemberLookup
public struct LanguageModelCallStartEvent: Sendable {
    public let callId: String
    public let provider: String
    public let modelId: String
    public let instructions: Instructions?
    public let messages: [ModelMessage]
    /// The tools sent to the provider.
    public let tools: [LanguageModelV4Tool]?
    public let callOptions: LanguageModelCallOptions

    public init(
        callId: String,
        provider: String,
        modelId: String,
        instructions: Instructions?,
        messages: [ModelMessage],
        tools: [LanguageModelV4Tool]?,
        callOptions: LanguageModelCallOptions
    ) {
        self.callId = callId
        self.provider = provider
        self.modelId = modelId
        self.instructions = instructions
        self.messages = messages
        self.tools = tools
        self.callOptions = callOptions
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<LanguageModelCallOptions, T>) -> T {
        callOptions[keyPath: keyPath]
    }
}

/// Performance of a single language model call.
public struct LanguageModelCallPerformance: Sendable, Equatable {
    public let responseTimeMs: Double
    public let effectiveOutputTokensPerSecond: Double
    public let outputTokensPerSecond: Double?
    public let inputTokensPerSecond: Double?
    public let effectiveTotalTokensPerSecond: Double
    public let timeToFirstOutputMs: Double?
    public let timeBetweenOutputChunksMs: OutputChunkTimingStats?

    public init(
        responseTimeMs: Double,
        effectiveOutputTokensPerSecond: Double,
        outputTokensPerSecond: Double? = nil,
        inputTokensPerSecond: Double? = nil,
        effectiveTotalTokensPerSecond: Double,
        timeToFirstOutputMs: Double? = nil,
        timeBetweenOutputChunksMs: OutputChunkTimingStats? = nil
    ) {
        self.responseTimeMs = responseTimeMs
        self.effectiveOutputTokensPerSecond = effectiveOutputTokensPerSecond
        self.outputTokensPerSecond = outputTokensPerSecond
        self.inputTokensPerSecond = inputTokensPerSecond
        self.effectiveTotalTokensPerSecond = effectiveTotalTokensPerSecond
        self.timeToFirstOutputMs = timeToFirstOutputMs
        self.timeBetweenOutputChunksMs = timeBetweenOutputChunksMs
    }
}

/**
 Event passed to `onLanguageModelCallEnd` after the model response has been
 normalized and parsed, before client-side tool execution.

 Port of `LanguageModelCallEndEvent` from `@ai-sdk/ai/src/generate-text/language-model-events.ts`.
 */
public struct LanguageModelCallEndEvent: Sendable {
    public let callId: String
    public let provider: String
    public let modelId: String
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let content: [ContentPart]
    public let responseId: String
    public let providerMetadata: ProviderMetadata?
    public let performance: LanguageModelCallPerformance

    public init(
        callId: String,
        provider: String,
        modelId: String,
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        content: [ContentPart],
        responseId: String,
        providerMetadata: ProviderMetadata?,
        performance: LanguageModelCallPerformance
    ) {
        self.callId = callId
        self.provider = provider
        self.modelId = modelId
        self.finishReason = finishReason
        self.usage = usage
        self.content = content
        self.responseId = responseId
        self.providerMetadata = providerMetadata
        self.performance = performance
    }
}

public typealias OnLanguageModelCallStartCallback = @Sendable (LanguageModelCallStartEvent) async throws -> Void
public typealias OnLanguageModelCallEndCallback = @Sendable (LanguageModelCallEndEvent) async throws -> Void

/**
 Event passed to `onToolExecutionStart` right before a tool's execute function runs.

 Port of `ToolExecutionStartEvent` from `@ai-sdk/ai/src/generate-text/tool-execution-events.ts`.
 */
public struct ToolExecutionStartEvent: Sendable {
    public let callId: String
    public let messages: [ModelMessage]
    public let toolCall: TypedToolCall
    /// The validated context of the tool.
    public let toolContext: Context?

    public init(callId: String, messages: [ModelMessage], toolCall: TypedToolCall, toolContext: Context?) {
        self.callId = callId
        self.messages = messages
        self.toolCall = toolCall
        self.toolContext = toolContext
    }

    func with(toolContext: Context?) -> ToolExecutionStartEvent {
        ToolExecutionStartEvent(callId: callId, messages: messages, toolCall: toolCall, toolContext: toolContext)
    }
}

/**
 Event passed to `onToolExecutionEnd` right after a tool's execute function completes or fails.

 Port of `ToolExecutionEndEvent` from `@ai-sdk/ai/src/generate-text/tool-execution-events.ts`.
 */
public struct ToolExecutionEndEvent: Sendable {
    public let callId: String
    public let messages: [ModelMessage]
    public let toolCall: TypedToolCall
    public let toolContext: Context?
    /// The tool result or tool error.
    public let toolOutput: ToolOutput
    /// Execution time in milliseconds.
    public let toolExecutionMs: Double

    public init(
        callId: String,
        messages: [ModelMessage],
        toolCall: TypedToolCall,
        toolContext: Context?,
        toolOutput: ToolOutput,
        toolExecutionMs: Double
    ) {
        self.callId = callId
        self.messages = messages
        self.toolCall = toolCall
        self.toolContext = toolContext
        self.toolOutput = toolOutput
        self.toolExecutionMs = toolExecutionMs
    }

    /// Whether the tool execution succeeded.
    public var success: Bool {
        if case .result = toolOutput { return true }
        return false
    }

    func with(toolContext: Context?) -> ToolExecutionEndEvent {
        ToolExecutionEndEvent(
            callId: callId, messages: messages, toolCall: toolCall, toolContext: toolContext,
            toolOutput: toolOutput, toolExecutionMs: toolExecutionMs
        )
    }
}

public typealias OnToolExecutionStartCallback = @Sendable (ToolExecutionStartEvent) async throws -> Void
public typealias OnToolExecutionEndCallback = @Sendable (ToolExecutionEndEvent) async throws -> Void
