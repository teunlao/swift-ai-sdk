import AISDKProvider
import AISDKProviderUtils

/**
 Applies default instructions to a language model when a call does not already
 contain a system message.

 Port of `@ai-sdk/ai/src/middleware/default-instructions-middleware.ts`. Upstream
 takes `Instructions` (`string | SystemModelMessage | SystemModelMessage[]`);
 Swift takes each form as an overload.
 */
public func defaultInstructionsMiddleware(instructions: String) -> LanguageModelV4Middleware {
    makeDefaultInstructionsMiddleware([.system(content: instructions, providerOptions: nil)])
}

public func defaultInstructionsMiddleware(instructions: SystemModelMessage) -> LanguageModelV4Middleware {
    defaultInstructionsMiddleware(instructions: [instructions])
}

public func defaultInstructionsMiddleware(instructions: [SystemModelMessage]) -> LanguageModelV4Middleware {
    makeDefaultInstructionsMiddleware(instructions.map {
        .system(content: $0.content, providerOptions: $0.providerOptions)
    })
}

private func makeDefaultInstructionsMiddleware(
    _ defaultSystemMessages: LanguageModelV4Prompt
) -> LanguageModelV4Middleware {
    LanguageModelV4Middleware(
        transformParams: { _, params, _ in
            let hasSystemMessage = params.prompt.contains {
                if case .system = $0 { return true }
                return false
            }
            if defaultSystemMessages.isEmpty || hasSystemMessage {
                return params
            }
            return LanguageModelV4CallOptions(
                prompt: defaultSystemMessages + params.prompt,
                maxOutputTokens: params.maxOutputTokens,
                temperature: params.temperature,
                stopSequences: params.stopSequences,
                topP: params.topP,
                topK: params.topK,
                presencePenalty: params.presencePenalty,
                frequencyPenalty: params.frequencyPenalty,
                responseFormat: params.responseFormat,
                seed: params.seed,
                tools: params.tools,
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
