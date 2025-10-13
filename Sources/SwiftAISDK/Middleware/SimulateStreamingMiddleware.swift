/**
 Simulates streaming chunks with the response from a generate call.

 Port of `@ai-sdk/ai/src/middleware/simulate-streaming-middleware.ts`.

 This middleware converts a non-streaming generate result into a stream by
 emitting appropriate stream parts for text, reasoning, and other content types.

 **Note**: Full tests pending Block E implementation (requires `streamText()` function).
 See upstream tests: `simulate-streaming-middleware.test.ts`
 */

import Foundation

/**
 Creates a middleware that simulates streaming from a generate result.

 This middleware wraps the streaming operation by calling `doGenerate()` instead
 of `doStream()`, then converting the result into stream parts.

 - Returns: A middleware that simulates streaming behavior.

 Example usage:
 ```swift
 let model = wrapLanguageModel(
     model: baseModel,
     middleware: simulateStreamingMiddleware()
 )
 ```
 */
public func simulateStreamingMiddleware() -> LanguageModelV3Middleware {
    return LanguageModelV3Middleware(
        middlewareVersion: "v3",
        wrapStream: { doGenerate, _, _, _ in
            // Call generate instead of stream
            let result = try await doGenerate()

            var id = 0

            // Create simulated stream
            let simulatedStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
                // Emit stream-start with warnings
                continuation.yield(.streamStart(warnings: result.warnings))

                // Emit response-metadata
                if let response = result.response {
                    continuation.yield(.responseMetadata(
                        id: response.id,
                        modelId: response.modelId,
                        timestamp: response.timestamp
                    ))
                }

                // Process content parts
                for content in result.content {
                    switch content {
                    case .text(let textContent):
                        // Only emit text parts if text is non-empty
                        if !textContent.text.isEmpty {
                            continuation.yield(.textStart(id: String(id), providerMetadata: textContent.providerMetadata))
                            continuation.yield(.textDelta(id: String(id), delta: textContent.text, providerMetadata: textContent.providerMetadata))
                            continuation.yield(.textEnd(id: String(id), providerMetadata: textContent.providerMetadata))
                            id += 1
                        }

                    case .reasoning(let reasoningContent):
                        // Emit reasoning parts
                        continuation.yield(.reasoningStart(id: String(id), providerMetadata: reasoningContent.providerMetadata))
                        continuation.yield(.reasoningDelta(id: String(id), delta: reasoningContent.text, providerMetadata: reasoningContent.providerMetadata))
                        continuation.yield(.reasoningEnd(id: String(id), providerMetadata: reasoningContent.providerMetadata))
                        id += 1

                    case .toolCall(let toolCall):
                        // Pass through tool-calls as-is
                        continuation.yield(.toolCall(toolCall))

                    case .toolResult(let toolResult):
                        // Pass through tool-results as-is
                        continuation.yield(.toolResult(toolResult))

                    case .file(let file):
                        // Pass through files as-is
                        continuation.yield(.file(file))

                    case .source(let source):
                        // Pass through sources as-is
                        continuation.yield(.source(source))
                    }
                }

                // Emit finish
                continuation.yield(.finish(
                    finishReason: result.finishReason,
                    usage: result.usage,
                    providerMetadata: result.providerMetadata
                ))

                // Close stream
                continuation.finish()
            }

            return LanguageModelV3StreamResult(
                stream: simulatedStream,
                request: result.request,
                response: result.response.map { response in
                    LanguageModelV3StreamResponseInfo(headers: response.headers)
                }
            )
        }
    )
}
