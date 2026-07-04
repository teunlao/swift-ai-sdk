import SwiftAISDK

func addToLastUserMessage(text: String, params: LanguageModelV4CallOptions) -> LanguageModelV4CallOptions {
  guard let lastMessage = params.prompt.last else { return params }
  guard case .user(let content, let providerOptions) = lastMessage else { return params }

  let updatedPrompt: LanguageModelV4Prompt =
    params.prompt.dropLast()
    + [
      .user(
        content: [.text(LanguageModelV4TextPart(text: text))] + content,
        providerOptions: providerOptions
      )
    ]

  return LanguageModelV4CallOptions(
    prompt: Array(updatedPrompt),
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
