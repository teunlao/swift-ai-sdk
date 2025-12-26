import SwiftAISDK

func addToLastUserMessage(text: String, params: LanguageModelV3CallOptions) -> LanguageModelV3CallOptions {
  guard let lastMessage = params.prompt.last else { return params }
  guard case .user(let content, let providerOptions) = lastMessage else { return params }

  let updatedPrompt: LanguageModelV3Prompt =
    params.prompt.dropLast()
    + [
      .user(
        content: [.text(LanguageModelV3TextPart(text: text))] + content,
        providerOptions: providerOptions
      )
    ]

  return LanguageModelV3CallOptions(
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
    providerOptions: params.providerOptions
  )
}

