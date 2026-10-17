/**
 Simulates streaming chunks with the response from a generate call.

 Port of `@ai-sdk/ai/src/middleware/simulate-streaming-middleware.ts`.

 The stream operation calls `doGenerate()` and replays its result as
 `stream-start`, `response-metadata`, one start/delta/end block per text and
 reasoning part, every other content part as is, and `finish`.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Creates a middleware that simulates streaming from a generate result.
public func simulateStreamingMiddleware() -> LanguageModelV4Middleware {
    LanguageModelV4Middleware(
        wrapStream: { doGenerate, _, _, _ in
            let result = try await doGenerate()

            var parts: [LanguageModelV4StreamPart] = [
                .streamStart(warnings: result.warnings),
                .responseMetadata(
                    id: result.response?.id,
                    modelId: result.response?.modelId,
                    timestamp: result.response?.timestamp
                ),
            ]

            var id = 0
            for content in result.content {
                switch content {
                case .text(let text):
                    guard !text.text.isEmpty || !(text.citations ?? []).isEmpty else { continue }
                    parts.append(.textStart(id: String(id), providerMetadata: text.providerMetadata))
                    parts.append(.textDelta(id: String(id), delta: text.text, providerMetadata: nil))
                    parts.append(.textEnd(id: String(id), providerMetadata: nil, citations: text.citations))
                    id += 1
                case .reasoning(let reasoning):
                    parts.append(.reasoningStart(id: String(id), providerMetadata: reasoning.providerMetadata))
                    parts.append(.reasoningDelta(id: String(id), delta: reasoning.text, providerMetadata: nil))
                    parts.append(.reasoningEnd(id: String(id), providerMetadata: nil))
                    id += 1
                case .toolCall(let toolCall):
                    parts.append(.toolCall(toolCall))
                case .toolResult(let toolResult):
                    parts.append(.toolResult(toolResult))
                case .toolApprovalRequest(let request):
                    parts.append(.toolApprovalRequest(request))
                case .custom(let custom):
                    parts.append(.custom(custom))
                case .file(let file):
                    parts.append(.file(file))
                case .reasoningFile(let file):
                    parts.append(.reasoningFile(file))
                case .source(let source):
                    parts.append(.source(source))
                }
            }

            parts.append(.finish(
                finishReason: result.finishReason,
                usage: result.usage,
                providerMetadata: result.providerMetadata
            ))

            return LanguageModelV4StreamResult(
                stream: replay(parts),
                request: result.request,
                response: result.response.map { LanguageModelV4StreamResponseInfo(headers: $0.headers) }
            )
        }
    )
}

private func replay<Part: Sendable>(_ parts: [Part]) -> AsyncThrowingStream<Part, Error> {
    AsyncThrowingStream { continuation in
        for part in parts {
            continuation.yield(part)
        }
        continuation.finish()
    }
}
