import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Result of a `generateText` call.

 Port of `@ai-sdk/ai/src/generate-text/generate-text-result.ts`. Content, files,
 sources, tool calls, tool results and warnings aggregate every step; text,
 reasoning, finish reason, request, response and provider metadata come from
 the final step.
 */
public protocol GenerateTextResult: Sendable {
    /// Structured output type.
    associatedtype Output: Sendable

    /// The content generated in all steps.
    var content: [ContentPart] { get }

    /// Text generated in the final step.
    var text: String { get }

    /// Reasoning generated in the final step.
    var reasoning: [ReasoningOutput] { get }

    /// Reasoning text of the final step, `nil` when there is none.
    var reasoningText: String? { get }

    /// Files generated in all steps.
    var files: [GeneratedFile] { get }

    /// Sources used in all steps.
    var sources: [Source] { get }

    /// Tool calls of all steps.
    var toolCalls: [TypedToolCall] { get }
    var staticToolCalls: [StaticToolCall] { get }
    var dynamicToolCalls: [DynamicToolCall] { get }

    /// Tool results of all steps.
    var toolResults: [TypedToolResult] { get }
    var staticToolResults: [StaticToolResult] { get }
    var dynamicToolResults: [DynamicToolResult] { get }

    /// Finish reason of the final step.
    var finishReason: FinishReason { get }

    /// Raw finish reason of the final step.
    var rawFinishReason: String? { get }

    /// Total usage of all steps.
    var usage: LanguageModelUsage { get }

    /// Total usage of all steps.
    var totalUsage: LanguageModelUsage { get }

    /// Warnings of all steps.
    var warnings: [CallWarning]? { get }

    /// Request metadata of the final step.
    var request: LanguageModelRequestMetadata { get }

    /// Response metadata of the final step.
    var response: StepResultResponse { get }

    /// Response messages of all steps, after the messages produced by
    /// pre-loop tool approval handling.
    var responseMessages: [ResponseMessage] { get }

    /// Provider metadata of the final step.
    var providerMetadata: ProviderMetadata? { get }

    /// All steps.
    var steps: [StepResult] { get }

    /// The final step.
    var finalStep: StepResult { get }

    /**
     The parsed structured output.

     - Throws: `NoOutputGeneratedError` when no output was parsed (the final
       step finished with tool calls, or produced no text without a stop).
     */
    var output: Output { get throws }
}

/**
 Default implementation of `GenerateTextResult`.

 Port of `@ai-sdk/ai/src/generate-text/default-generate-text-result.ts`.
 */
public final class DefaultGenerateTextResult<OutputValue: Sendable>: GenerateTextResult {
    public typealias Output = OutputValue

    public let steps: [StepResult]
    public let totalUsage: LanguageModelUsage

    private let initialResponseMessages: [ResponseMessage]
    private let resolvedOutput: OutputValue?

    public init(
        initialResponseMessages: [ResponseMessage] = [],
        steps: [StepResult],
        totalUsage: LanguageModelUsage,
        resolvedOutput: OutputValue?
    ) {
        precondition(!steps.isEmpty, "DefaultGenerateTextResult requires at least one step.")
        self.initialResponseMessages = initialResponseMessages
        self.steps = steps
        self.totalUsage = totalUsage
        self.resolvedOutput = resolvedOutput
    }

    public var finalStep: StepResult { steps[steps.count - 1] }

    public var content: [ContentPart] { steps.flatMap(\.content) }
    public var text: String { finalStep.text }
    public var reasoning: [ReasoningOutput] { finalStep.reasoning }
    public var reasoningText: String? { finalStep.reasoningText }
    public var files: [GeneratedFile] { steps.flatMap(\.files) }
    public var sources: [Source] { steps.flatMap(\.sources) }
    public var toolCalls: [TypedToolCall] { steps.flatMap(\.toolCalls) }
    public var staticToolCalls: [StaticToolCall] { steps.flatMap(\.staticToolCalls) }
    public var dynamicToolCalls: [DynamicToolCall] { steps.flatMap(\.dynamicToolCalls) }
    public var toolResults: [TypedToolResult] { steps.flatMap(\.toolResults) }
    public var staticToolResults: [StaticToolResult] { steps.flatMap(\.staticToolResults) }
    public var dynamicToolResults: [DynamicToolResult] { steps.flatMap(\.dynamicToolResults) }
    public var finishReason: FinishReason { finalStep.finishReason }
    public var rawFinishReason: String? { finalStep.rawFinishReason }
    public var usage: LanguageModelUsage { totalUsage }
    public var warnings: [CallWarning]? { steps.flatMap { $0.warnings ?? [] } }
    public var request: LanguageModelRequestMetadata { finalStep.request }
    public var response: StepResultResponse { finalStep.response }
    public var providerMetadata: ProviderMetadata? { finalStep.providerMetadata }

    public var responseMessages: [ResponseMessage] {
        initialResponseMessages + steps.flatMap(\.response.messages)
    }

    public var output: OutputValue {
        get throws {
            guard let resolvedOutput else {
                throw NoOutputGeneratedError()
            }
            return resolvedOutput
        }
    }
}
