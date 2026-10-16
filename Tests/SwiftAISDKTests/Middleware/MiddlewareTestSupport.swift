import Foundation
import AISDKProvider
import SwiftAISDK

let middlewareTestPrompt: LanguageModelV4Prompt = [
    .user(content: [.text(LanguageModelV4TextPart(text: "Hello, world!"))], providerOptions: nil)
]

let middlewareTestUsage = LanguageModelV4Usage(
    inputTokens: .init(total: 5, noCache: 5, cacheRead: 0, cacheWrite: 0),
    outputTokens: .init(total: 10, text: 10, reasoning: 0)
)

let middlewareTestFinish = LanguageModelV4StreamPart.finish(
    finishReason: .init(unified: .stop, raw: "stop"),
    usage: middlewareTestUsage,
    providerMetadata: nil
)

/// Streams `parts` from a mock model wrapped with `middleware` and collects the output.
func streamThroughMiddleware(
    _ middleware: LanguageModelV4Middleware,
    _ parts: [LanguageModelV4StreamPart]
) async throws -> [LanguageModelV4StreamPart] {
    let model = MockLanguageModelV4(doStream: .singleValue(LanguageModelV4StreamResult(stream: makeAsyncStream(from: parts))))
    let result = try await wrapLanguageModel(model: model, middleware: middleware)
        .doStream(options: LanguageModelV4CallOptions(prompt: middlewareTestPrompt))
    return try await collectStream(result.stream)
}

/// Generates `content` from a mock model wrapped with `middleware` and returns the resulting content.
func generateThroughMiddleware(
    _ middleware: LanguageModelV4Middleware,
    _ content: [LanguageModelV4Content]
) async throws -> [LanguageModelV4Content] {
    let model = MockLanguageModelV4(doGenerate: .singleValue(LanguageModelV4GenerateResult(
        content: content,
        finishReason: .init(unified: .stop, raw: "stop"),
        usage: middlewareTestUsage
    )))
    return try await wrapLanguageModel(model: model, middleware: middleware)
        .doGenerate(options: LanguageModelV4CallOptions(prompt: middlewareTestPrompt))
        .content
}

/// Joins the text deltas of `parts`, or `nil` when there are none.
func textDeltas(_ parts: [LanguageModelV4StreamPart]) -> String? {
    let deltas = parts.compactMap { part -> String? in
        if case .textDelta(_, let delta, _) = part { return delta }
        return nil
    }
    return deltas.isEmpty ? nil : deltas.joined()
}

/// Joins the reasoning deltas of `parts`, or `nil` when there are none.
func reasoningDeltas(_ parts: [LanguageModelV4StreamPart]) -> String? {
    let deltas = parts.compactMap { part -> String? in
        if case .reasoningDelta(_, let delta, _) = part { return delta }
        return nil
    }
    return deltas.isEmpty ? nil : deltas.joined()
}
