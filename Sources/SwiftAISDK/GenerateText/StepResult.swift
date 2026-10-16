import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Tool contexts keyed by tool name.

 Port of upstream `InferToolSetContext<TOOLS>` for the untyped Swift `ToolSet`.
 */
public typealias ToolsContext = [String: Context]

/// Provider and model that produced a result.
public struct ModelInfo: Sendable, Equatable {
    public let provider: String
    public let modelId: String

    public init(provider: String, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }
}

/**
 Timing statistics for the intervals between output chunks.

 Port of `OutputChunkTimingStats` from `@ai-sdk/ai/src/generate-text/step-result.ts`.
 */
public struct OutputChunkTimingStats: Sendable, Equatable, Codable {
    public let min: Double
    public let p10: Double
    public let median: Double
    public let avg: Double
    public let p90: Double
    public let max: Double

    public init(min: Double, p10: Double, median: Double, avg: Double, p90: Double, max: Double) {
        self.min = min
        self.p10 = p10
        self.median = median
        self.avg = avg
        self.p90 = p90
        self.max = max
    }
}

/**
 Performance metrics of a step.

 Port of `StepResultPerformance` from `@ai-sdk/ai/src/generate-text/step-result.ts`.
 */
public struct StepResultPerformance: Sendable, Equatable, Codable {
    /// Output tokens per second over the model response time.
    public let effectiveOutputTokensPerSecond: Double

    /// Output tokens per second after the first output chunk (streaming only).
    public let outputTokensPerSecond: Double?

    /// Input tokens per second until the first output chunk (streaming only).
    public let inputTokensPerSecond: Double?

    /// Input and output tokens per second over the model response time.
    public let effectiveTotalTokensPerSecond: Double

    /// Duration of the whole step, including tool execution, in milliseconds.
    public let stepTimeMs: Double

    /// Duration of the model response in milliseconds.
    public let responseTimeMs: Double

    /// Tool execution durations in milliseconds, keyed by tool call id.
    public let toolExecutionMs: [String: Double]

    /// Time until the first output chunk in milliseconds (streaming only).
    public let timeToFirstOutputMs: Double?

    /// Intervals between output chunks (streaming only).
    public let timeBetweenOutputChunksMs: OutputChunkTimingStats?

    public init(
        effectiveOutputTokensPerSecond: Double,
        outputTokensPerSecond: Double? = nil,
        inputTokensPerSecond: Double? = nil,
        effectiveTotalTokensPerSecond: Double,
        stepTimeMs: Double,
        responseTimeMs: Double,
        toolExecutionMs: [String: Double] = [:],
        timeToFirstOutputMs: Double? = nil,
        timeBetweenOutputChunksMs: OutputChunkTimingStats? = nil
    ) {
        self.effectiveOutputTokensPerSecond = effectiveOutputTokensPerSecond
        self.outputTokensPerSecond = outputTokensPerSecond
        self.inputTokensPerSecond = inputTokensPerSecond
        self.effectiveTotalTokensPerSecond = effectiveTotalTokensPerSecond
        self.stepTimeMs = stepTimeMs
        self.responseTimeMs = responseTimeMs
        self.toolExecutionMs = toolExecutionMs
        self.timeToFirstOutputMs = timeToFirstOutputMs
        self.timeBetweenOutputChunksMs = timeBetweenOutputChunksMs
    }

    /// Zero metrics.
    public static let empty = StepResultPerformance(
        effectiveOutputTokensPerSecond: 0,
        effectiveTotalTokensPerSecond: 0,
        stepTimeMs: 0,
        responseTimeMs: 0
    )
}

/**
 The result of a single step in the generation process.

 Port of `@ai-sdk/ai/src/generate-text/step-result.ts`.
 */
public protocol StepResult: Sendable {
    /// Unique identifier of the generation call this step belongs to.
    var callId: String { get }

    /// Zero-based index of this step.
    var stepNumber: Int { get }

    /// The model that produced this step.
    var model: ModelInfo { get }

    /// Tool contexts used in this step.
    var toolsContext: ToolsContext { get }

    /// Runtime context of this step.
    var runtimeContext: Context { get }

    /// Content generated in this step.
    var content: [ContentPart] { get }

    /// Generated text.
    var text: String { get }

    /// Reasoning parts.
    var reasoning: [ReasoningOutput] { get }

    /// Reasoning text, `nil` when there is no reasoning text.
    var reasoningText: String? { get }

    /// Generated files.
    var files: [GeneratedFile] { get }

    /// Sources used as references.
    var sources: [Source] { get }

    var toolCalls: [TypedToolCall] { get }
    var staticToolCalls: [StaticToolCall] { get }
    var dynamicToolCalls: [DynamicToolCall] { get }
    var toolResults: [TypedToolResult] { get }
    var staticToolResults: [StaticToolResult] { get }
    var dynamicToolResults: [DynamicToolResult] { get }

    /// Unified finish reason.
    var finishReason: FinishReason { get }

    /// Raw finish reason from the provider.
    var rawFinishReason: String? { get }

    /// Token usage of this step.
    var usage: LanguageModelUsage { get }

    /// Performance metrics of this step.
    var performance: StepResultPerformance { get }

    /// Warnings from the provider.
    var warnings: [CallWarning]? { get }

    /// Request metadata.
    var request: LanguageModelRequestMetadata { get }

    /// Response metadata, including the response messages of this step.
    var response: StepResultResponse { get }

    /// Provider-specific metadata.
    var providerMetadata: ProviderMetadata? { get }
}

/**
 Response metadata of a step: `LanguageModelResponseMetadata` with the step's
 response messages and optional body.
 */
public struct StepResultResponse: Sendable, Equatable {
    /// ID for the generated response.
    public let id: String

    /// Timestamp for the start of the generated response.
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response.
    public let modelId: String

    /// Response headers (available only for providers that use HTTP requests).
    public let headers: [String: String]?

    /// The response messages that were generated during this step.
    public let messages: [ResponseMessage]

    /// Response body, when retained (`include.responseBody`).
    public let body: JSONValue?

    public init(
        id: String,
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil,
        messages: [ResponseMessage],
        body: JSONValue? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.messages = messages
        self.body = body
    }

    /// Create from `LanguageModelResponseMetadata` with messages and optional body.
    public init(
        from metadata: LanguageModelResponseMetadata,
        messages: [ResponseMessage],
        body: JSONValue? = nil
    ) {
        self.init(
            id: metadata.id,
            timestamp: metadata.timestamp,
            modelId: metadata.modelId,
            headers: metadata.headers,
            messages: messages,
            body: body
        )
    }

    /// The response metadata without messages and body.
    public var metadata: LanguageModelResponseMetadata {
        LanguageModelResponseMetadata(id: id, timestamp: timestamp, modelId: modelId, headers: headers)
    }
}

/**
 Default implementation of `StepResult`.

 Port of `DefaultStepResult` from `@ai-sdk/ai/src/generate-text/step-result.ts`.
 */
public final class DefaultStepResult: StepResult {
    public let callId: String
    public let stepNumber: Int
    public let model: ModelInfo
    public let toolsContext: ToolsContext
    public let runtimeContext: Context
    public let content: [ContentPart]
    public let finishReason: FinishReason
    public let rawFinishReason: String?
    public let usage: LanguageModelUsage
    public let performance: StepResultPerformance
    public let warnings: [CallWarning]?
    public let request: LanguageModelRequestMetadata
    public let response: StepResultResponse
    public let providerMetadata: ProviderMetadata?

    public init(
        callId: String = "",
        stepNumber: Int = 0,
        model: ModelInfo = ModelInfo(provider: "", modelId: ""),
        toolsContext: ToolsContext = [:],
        runtimeContext: Context = [:],
        content: [ContentPart],
        finishReason: FinishReason,
        rawFinishReason: String? = nil,
        usage: LanguageModelUsage,
        performance: StepResultPerformance = .empty,
        warnings: [CallWarning]? = nil,
        request: LanguageModelRequestMetadata,
        response: StepResultResponse,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.callId = callId
        self.stepNumber = stepNumber
        self.model = model
        self.toolsContext = toolsContext
        self.runtimeContext = runtimeContext
        self.content = content
        self.finishReason = finishReason
        self.rawFinishReason = rawFinishReason
        self.usage = usage
        self.performance = performance
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    /// The same step with different contexts (used to restrict telemetry).
    func with(runtimeContext: Context, toolsContext: ToolsContext) -> DefaultStepResult {
        DefaultStepResult(
            callId: callId,
            stepNumber: stepNumber,
            model: model,
            toolsContext: toolsContext,
            runtimeContext: runtimeContext,
            content: content,
            finishReason: finishReason,
            rawFinishReason: rawFinishReason,
            usage: usage,
            performance: performance,
            warnings: warnings,
            request: request,
            response: response,
            providerMetadata: providerMetadata
        )
    }

    public var text: String {
        content.compactMap { part -> String? in
            if case .text(let text, _, _) = part { return text }
            return nil
        }.joined()
    }

    public var reasoning: [ReasoningOutput] {
        content.compactMap { part in
            if case .reasoning(let output) = part { return output }
            return nil
        }
    }

    public var reasoningText: String? {
        let text = reasoning.map(\.text).joined()
        return text.isEmpty ? nil : text
    }

    public var files: [GeneratedFile] {
        content.compactMap { part in
            if case .file(let file, _) = part { return file }
            return nil
        }
    }

    public var sources: [Source] {
        content.compactMap { part in
            if case .source(_, let source) = part { return source }
            return nil
        }
    }

    public var toolCalls: [TypedToolCall] {
        content.compactMap { part in
            if case .toolCall(let toolCall, _) = part { return toolCall }
            return nil
        }
    }

    public var staticToolCalls: [StaticToolCall] {
        toolCalls.compactMap { toolCall in
            if case .static(let call) = toolCall { return call }
            return nil
        }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        toolCalls.compactMap { toolCall in
            if case .dynamic(let call) = toolCall { return call }
            return nil
        }
    }

    public var toolResults: [TypedToolResult] {
        content.compactMap { part in
            if case .toolResult(let result, _) = part { return result }
            return nil
        }
    }

    public var toolErrors: [TypedToolError] {
        content.compactMap { part in
            if case .toolError(let error, _) = part { return error }
            return nil
        }
    }

    public var staticToolResults: [StaticToolResult] {
        toolResults.compactMap { result in
            if case .static(let staticResult) = result { return staticResult }
            return nil
        }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        toolResults.compactMap { result in
            if case .dynamic(let dynamicResult) = result { return dynamicResult }
            return nil
        }
    }
}
