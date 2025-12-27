import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Result type returned by `generateText`.

 Port of `@ai-sdk/ai/src/generate-text/generate-text-result.ts`.

 The result aggregates information from all generation steps and exposes
 the outputs produced in the final step, including generated content,
 tool interactions, usage statistics, and provider metadata.
 */
public protocol GenerateTextResult: Sendable {
    /// Structured output type produced via experimental_output.
    associatedtype Output: Sendable

    /// The content generated in the final step.
    var content: [ContentPart] { get }

    /// Generated text from the final step.
    var text: String { get }

    /// Generated reasoning outputs from the final step.
    var reasoning: [ReasoningOutput] { get }

    /// Combined reasoning text from the final step, if available.
    var reasoningText: String? { get }

    /// Files produced in the final step.
    var files: [GeneratedFile] { get }

    /// Source references produced in the final step.
    var sources: [Source] { get }

    /// Tool calls executed in the final step.
    var toolCalls: [TypedToolCall] { get }

    /// Static tool calls executed in the final step.
    var staticToolCalls: [StaticToolCall] { get }

    /// Dynamic tool calls executed in the final step.
    var dynamicToolCalls: [DynamicToolCall] { get }

    /// Tool results produced in the final step.
    var toolResults: [TypedToolResult] { get }

    /// Static tool results produced in the final step.
    var staticToolResults: [StaticToolResult] { get }

    /// Dynamic tool results produced in the final step.
    var dynamicToolResults: [DynamicToolResult] { get }

    /// Finish reason reported for the final step.
    var finishReason: FinishReason { get }

    /// Token usage of the final step.
    var usage: LanguageModelUsage { get }

    /// Aggregated token usage across all steps.
    var totalUsage: LanguageModelUsage { get }

    /// Provider warnings (e.g. unsupported settings) from the final step.
    var warnings: [CallWarning]? { get }

    /// Request metadata for the final step.
    var request: LanguageModelRequestMetadata { get }

    /// Response metadata for the final step.
    var response: StepResultResponse { get }

    /// Provider-specific metadata from the final step.
    var providerMetadata: ProviderMetadata? { get }

    /// All steps executed during the generation.
    var steps: [StepResult] { get }

    /**
     Structured output generated via `experimental_output`.

     - Throws: `NoOutputSpecifiedError` when no output parser was configured.
     */
    var experimentalOutput: Output { get throws }
}

public extension GenerateTextResult {
    /**
     Structured output generated via `experimental_output`, if specified.

     - Returns: The parsed structured output when available; otherwise `nil`.
     - Throws: Any error thrown by `experimentalOutput` other than `NoOutputSpecifiedError`.
     */
    var experimentalOutputIfSpecified: Output? {
        get throws {
            do {
                return try experimentalOutput
            } catch is NoOutputSpecifiedError {
                return nil
            }
        }
    }
}

/**
 Default implementation of `GenerateTextResult`.

 Mirrors the upstream `DefaultGenerateTextResult` class.
 */
public final class DefaultGenerateTextResult<OutputValue: Sendable>: GenerateTextResult {
    public typealias Output = OutputValue

    // MARK: - Stored Properties

    public let steps: [StepResult]
    public let totalUsage: LanguageModelUsage

    private let resolvedOutput: OutputValue?

    // MARK: - Initialization

    /**
     Create a default generate-text result.

     - Parameters:
       - steps: All step results produced during generation.
       - totalUsage: Aggregated usage across all steps.
       - resolvedOutput: Parsed structured output (if any).
     */
    public init(
        steps: [StepResult],
        totalUsage: LanguageModelUsage,
        resolvedOutput: OutputValue?
    ) {
        self.steps = steps
        self.totalUsage = totalUsage
        self.resolvedOutput = resolvedOutput
    }

    // MARK: - Helpers

    private var finalStep: StepResult {
        guard let last = steps.last else {
            preconditionFailure("DefaultGenerateTextResult requires at least one step.")
        }
        return last
    }

    // MARK: - GenerateTextResult

    public var content: [ContentPart] {
        finalStep.content
    }

    public var text: String {
        finalStep.text
    }

    public var reasoning: [ReasoningOutput] {
        finalStep.reasoning
    }

    public var reasoningText: String? {
        finalStep.reasoningText
    }

    public var files: [GeneratedFile] {
        finalStep.files
    }

    public var sources: [Source] {
        finalStep.sources
    }

    public var toolCalls: [TypedToolCall] {
        finalStep.toolCalls
    }

    public var staticToolCalls: [StaticToolCall] {
        finalStep.staticToolCalls
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        finalStep.dynamicToolCalls
    }

    public var toolResults: [TypedToolResult] {
        finalStep.toolResults
    }

    public var staticToolResults: [StaticToolResult] {
        finalStep.staticToolResults
    }

    public var dynamicToolResults: [DynamicToolResult] {
        finalStep.dynamicToolResults
    }

    public var finishReason: FinishReason {
        finalStep.finishReason
    }

    public var usage: LanguageModelUsage {
        finalStep.usage
    }

    public var warnings: [CallWarning]? {
        finalStep.warnings
    }

    public var request: LanguageModelRequestMetadata {
        finalStep.request
    }

    public var response: StepResultResponse {
        finalStep.response
    }

    public var providerMetadata: ProviderMetadata? {
        finalStep.providerMetadata
    }

    public var experimentalOutput: OutputValue {
        get throws {
            guard let output = resolvedOutput else {
                throw NoOutputSpecifiedError()
            }
            return output
        }
    }
}
