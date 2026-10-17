/**
 Middleware that appends input examples to tool descriptions.

 Port of `@ai-sdk/ai/src/middleware/add-tool-input-examples-middleware.ts`.

 This is useful for providers that don't natively support the `inputExamples`
 property. The middleware serializes examples into the tool's description text.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Configuration for `addToolInputExamplesMiddleware`.
public struct AddToolInputExamplesOptions: Sendable {
    /// A prefix to prepend before the examples.
    public let prefix: String

    /// Optional custom formatter for each example.
    /// Receives the example object and its index.
    public let format: (@Sendable (_ example: LanguageModelV4ToolInputExample, _ index: Int) -> String)?

    /// Whether to remove the `inputExamples` property after adding them to the description.
    public let remove: Bool

    public init(
        prefix: String = "Input Examples:",
        format: (@Sendable (_ example: LanguageModelV4ToolInputExample, _ index: Int) -> String)? = nil,
        remove: Bool = true
    ) {
        self.prefix = prefix
        self.format = format
        self.remove = remove
    }
}

/// Upstream `JSON.stringify(example.input)`. Swift objects carry no key order,
/// so keys are sorted to keep the description deterministic.
private func defaultFormatExample(_ example: LanguageModelV4ToolInputExample, index: Int) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(JSONValue.object(example.input)) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

/// Returns the description with the examples section appended, or `nil` when the tool has no examples.
private func describeExamples(
    _ inputExamples: [LanguageModelV4ToolInputExample]?,
    description: String?,
    options: AddToolInputExamplesOptions
) -> String? {
    guard let inputExamples, !inputExamples.isEmpty else { return nil }

    let format = options.format ?? { example, index in defaultFormatExample(example, index: index) }
    let formattedExamples = inputExamples.enumerated()
        .map { index, example in format(example, index) }
        .joined(separator: "\n")
    let examplesSection = "\(options.prefix)\n\(formattedExamples)"

    if let description, !description.isEmpty {
        return "\(description)\n\n\(examplesSection)"
    }
    return examplesSection
}

/**
 Creates a middleware that appends tool input examples to function tool descriptions.

 - Parameter options: Configuration options. Defaults mirror upstream behavior.
 - Returns: A language model middleware.
 */
public func addToolInputExamplesMiddleware(
    options: AddToolInputExamplesOptions = AddToolInputExamplesOptions()
) -> LanguageModelV4Middleware {
    LanguageModelV4Middleware(
        transformParams: { _, params, _ in
            guard let tools = params.tools, !tools.isEmpty else {
                return params
            }

            let transformedTools: [LanguageModelV4Tool] = tools.map { tool in
                guard case .function(let functionTool) = tool,
                      let toolDescription = describeExamples(
                          functionTool.inputExamples,
                          description: functionTool.description,
                          options: options
                      )
                else {
                    return tool
                }

                return .function(LanguageModelV4FunctionTool(
                    name: functionTool.name,
                    inputSchema: functionTool.inputSchema,
                    inputExamples: options.remove ? nil : functionTool.inputExamples,
                    description: toolDescription,
                    strict: functionTool.strict,
                    providerOptions: functionTool.providerOptions
                ))
            }

            return LanguageModelV4CallOptions(
                prompt: params.prompt,
                maxOutputTokens: params.maxOutputTokens,
                temperature: params.temperature,
                stopSequences: params.stopSequences,
                topP: params.topP,
                topK: params.topK,
                presencePenalty: params.presencePenalty,
                frequencyPenalty: params.frequencyPenalty,
                responseFormat: params.responseFormat,
                seed: params.seed,
                tools: transformedTools,
                toolChoice: params.toolChoice,
                includeRawChunks: params.includeRawChunks,
                abortSignal: params.abortSignal,
                headers: params.headers,
                reasoning: params.reasoning,
                providerOptions: params.providerOptions
            )
        }
    )
}

