import SwiftAISDK

let yourGuardrailMiddleware: LanguageModelV4Middleware = LanguageModelV4Middleware(
  wrapGenerate: { doGenerate, _, _, _ in
    let result = try await doGenerate()

    let cleanedContent: [LanguageModelV4Content] = result.content.map { part in
      switch part {
      case .text(let text):
        return .text(
          LanguageModelV4Text(
            text: text.text.replacingOccurrences(of: "badword", with: "<REDACTED>"),
            providerMetadata: text.providerMetadata
          )
        )
      default:
        return part
      }
    }

    return LanguageModelV4GenerateResult(
      content: cleanedContent,
      finishReason: result.finishReason,
      usage: result.usage,
      providerMetadata: result.providerMetadata,
      request: result.request,
      response: result.response,
      warnings: result.warnings
    )
  }
  // streaming guardrails intentionally not implemented (mirrors upstream comment)
)
