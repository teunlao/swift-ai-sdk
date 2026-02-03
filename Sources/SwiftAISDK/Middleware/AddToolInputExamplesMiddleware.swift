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
    public let format: (@Sendable (_ example: LanguageModelV3ToolInputExample, _ index: Int) -> String)?

    /// Whether to remove the `inputExamples` property after adding them to the description.
    public let remove: Bool

    public init(
        prefix: String = "Input Examples:",
        format: (@Sendable (_ example: LanguageModelV3ToolInputExample, _ index: Int) -> String)? = nil,
        remove: Bool = true
    ) {
        self.prefix = prefix
        self.format = format
        self.remove = remove
    }
}

private func defaultFormatExample(_ example: LanguageModelV3ToolInputExample, index: Int) -> String {
    (try? JSONValue.object(example.input).toJSONString(prettyPrinted: false, sortedKeys: true)) ?? "{}"
}

/**
 Creates a middleware that appends tool input examples to function tool descriptions.

 - Parameter options: Configuration options. Defaults mirror upstream behavior.
 - Returns: A language model middleware.
 */
public func addToolInputExamplesMiddleware(
    options: AddToolInputExamplesOptions = AddToolInputExamplesOptions()
) -> LanguageModelV3Middleware {
    LanguageModelV3Middleware(
        middlewareVersion: "v3",
        transformParams: { _, params, _ in
            guard let tools = params.tools, !tools.isEmpty else {
                return params
            }

            let format = options.format ?? { example, index in
                defaultFormatExample(example, index: index)
            }

            let transformedTools: [LanguageModelV3Tool] = tools.map { tool in
                guard case .function(let functionTool) = tool,
                      let inputExamples = functionTool.inputExamples,
                      !inputExamples.isEmpty
                else {
                    return tool
                }

                let formattedExamples = inputExamples.enumerated().map { index, example in
                    format(example, index)
                }.joined(separator: "\n")

                let examplesSection = "\(options.prefix)\n\(formattedExamples)"

                let baseDescription = functionTool.description
                let toolDescription: String
                if let baseDescription, !baseDescription.isEmpty {
                    toolDescription = "\(baseDescription)\n\n\(examplesSection)"
                } else {
                    toolDescription = examplesSection
                }

                let transformedTool = LanguageModelV3FunctionTool(
                    name: functionTool.name,
                    inputSchema: functionTool.inputSchema,
                    inputExamples: options.remove ? nil : inputExamples,
                    description: toolDescription,
                    strict: functionTool.strict,
                    providerOptions: functionTool.providerOptions
                )

                return .function(transformedTool)
            }

            return LanguageModelV3CallOptions(
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
                providerOptions: params.providerOptions
            )
        }
    )
}
