/**
 The result of a single step in the generation process.

 Port of `@ai-sdk/ai/src/generate-text/step-result.ts`.

 Represents the output from a single step in a multi-step text generation flow.
 Contains all content generated in the step, including text, reasoning, tool calls,
 and tool results, along with usage information and metadata.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 The result of a single step in the generation process.

 This protocol defines the interface for accessing all outputs from a generation step,
 including generated content, tool interactions, and metadata.
 */
public protocol StepResult: Sendable {
    /// The content that was generated in the last step.
    var content: [ContentPart] { get }

    /// The generated text.
    var text: String { get }

    /// The reasoning that was generated during the generation.
    var reasoning: [ReasoningOutput] { get }

    /// The reasoning text that was generated during the generation.
    var reasoningText: String? { get }

    /// The files that were generated during the generation.
    var files: [GeneratedFile] { get }

    /// The sources that were used to generate the text.
    var sources: [Source] { get }

    /// The tool calls that were made during the generation.
    var toolCalls: [TypedToolCall] { get }

    /// The static tool calls that were made in the last step.
    var staticToolCalls: [StaticToolCall] { get }

    /// The dynamic tool calls that were made in the last step.
    var dynamicToolCalls: [DynamicToolCall] { get }

    /// The results of the tool calls.
    var toolResults: [TypedToolResult] { get }

    /// The static tool results that were made in the last step.
    var staticToolResults: [StaticToolResult] { get }

    /// The dynamic tool results that were made in the last step.
    var dynamicToolResults: [DynamicToolResult] { get }

    /// The reason why the generation finished.
    var finishReason: FinishReason { get }

    /// The token usage of the generated text.
    var usage: LanguageModelUsage { get }

    /// Warnings from the model provider (e.g. unsupported settings).
    var warnings: [CallWarning]? { get }

    /// Additional request information.
    var request: LanguageModelRequestMetadata { get }

    /// Additional response information.
    var response: StepResultResponse { get }

    /// Additional provider-specific metadata.
    ///
    /// These are passed through from the provider to the AI SDK and enable
    /// provider-specific results that can be fully encapsulated in the provider.
    var providerMetadata: ProviderMetadata? { get }
}

/**
 Response information for a step result.

 Extends `LanguageModelResponseMetadata` with step-specific information like
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

    /// The response messages that were generated during the call.
    ///
    /// Response messages can be either assistant messages or tool messages.
    /// They contain a generated id.
    public let messages: [ResponseMessage]

    /// Response body (available only for providers that use HTTP requests).
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
        self.id = metadata.id
        self.timestamp = metadata.timestamp
        self.modelId = metadata.modelId
        self.headers = metadata.headers
        self.messages = messages
        self.body = body
    }
}

/**
 Default implementation of `StepResult`.

 This class provides a concrete implementation of the `StepResult` protocol,
 storing the generated content and computing derived properties on demand.
 */
public final class DefaultStepResult: StepResult {
    // MARK: - Stored Properties

    public let content: [ContentPart]
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let warnings: [CallWarning]?
    public let request: LanguageModelRequestMetadata
    public let response: StepResultResponse
    public let providerMetadata: ProviderMetadata?

    // MARK: - Initialization

    public init(
        content: [ContentPart],
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        warnings: [CallWarning]? = nil,
        request: LanguageModelRequestMetadata,
        response: StepResultResponse,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.content = content
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    // MARK: - Computed Properties

    public var text: String {
        content
            .compactMap { part -> String? in
                if case .text(let text, _) = part {
                    return text
                }
                return nil
            }
            .joined()
    }

    public var reasoning: [ReasoningOutput] {
        content.compactMap { part in
            if case .reasoning(let output) = part {
                return output
            }
            return nil
        }
    }

    public var reasoningText: String? {
        let reasoningParts = self.reasoning
        guard !reasoningParts.isEmpty else {
            return nil
        }
        return reasoningParts.map(\.text).joined()
    }

    public var files: [GeneratedFile] {
        content.compactMap { part in
            if case .file(let file, _) = part {
                return file
            }
            return nil
        }
    }

    public var sources: [Source] {
        content.compactMap { part in
            if case .source(_, let source) = part {
                return source
            }
            return nil
        }
    }

    public var toolCalls: [TypedToolCall] {
        content.compactMap { part in
            if case .toolCall(let toolCall, _) = part {
                return toolCall
            }
            return nil
        }
    }

    public var staticToolCalls: [StaticToolCall] {
        toolCalls.compactMap { toolCall in
            if case .static(let staticCall) = toolCall {
                return staticCall
            }
            return nil
        }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        toolCalls.compactMap { toolCall in
            if case .dynamic(let dynamicCall) = toolCall {
                return dynamicCall
            }
            return nil
        }
    }

    public var toolResults: [TypedToolResult] {
        content.compactMap { part in
            if case .toolResult(let result, _) = part {
                return result
            }
            return nil
        }
    }

    public var staticToolResults: [StaticToolResult] {
        toolResults.compactMap { result in
            if case .static(let staticResult) = result {
                return staticResult
            }
            return nil
        }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        toolResults.compactMap { result in
            if case .dynamic(let dynamicResult) = result {
                return dynamicResult
            }
            return nil
        }
    }
}
