import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import AISDKProvider

struct StreamTextOpenAIResponsesReasoningZeroDataRetentionExample: Example {
  static let name = "stream-text/openai-responses-reasoning-zero-data-retention"
  static let description = "Demonstrates Responses reasoning with store=false (no data retention)."

  static func run() async throws {
    let prompt = "Analyze the following encrypted data: U2VjcmV0UGFzc3dvcmQxMjM=. What type of encryption is this and what secret does it contain?"
    let followUpQuestion = "Based on your previous analysis, what security recommendations would you make?"

    let providerOptions = openai.options.responses(
      store: false,
      reasoningEffort: "medium",
      reasoningSummary: "auto"
    )

    do {
      // First request
      let firstResult = try streamText(
        model: openai.responses("o3-mini"),
        prompt: prompt,
        providerOptions: providerOptions
      )

      for try await _ in firstResult.textStream { }

      Logger.section("First request — reasoning")
      logReasoning(try await firstResult.reasoning)
      Logger.section("First request — answer")
      Logger.info(try await firstResult.text)

      Logger.section("First request — body")
      if let body = try await firstResult.request.body {
        Helpers.printJSON(body)
      } else {
        Logger.info("<none>")
      }

      // Second request replays conversation because store=false makes calls stateless.
      let previousMessages = (try await firstResult.response).messages.asModelMessages()
      let downstreamMessages: [ModelMessage] =
        [.user(prompt)] + previousMessages + [.user(followUpQuestion)]

      let secondResult = try streamText(
        model: openai.responses("o3-mini"),
        messages: downstreamMessages,
        providerOptions: providerOptions,
        onError: { error in
          Logger.error("Second request error: \(error.localizedDescription)")
          if let apiError = error as? APICallError,
             let values = apiError.requestBodyValues {
            Logger.section("Second request — errored body")
            Logger.info(String(describing: values))
          }
        }
      )

      for try await _ in secondResult.textStream { }

      Logger.section("Second request — reasoning")
      logReasoning(try await secondResult.reasoning)
      Logger.section("Second request — answer")
      Logger.info(try await secondResult.text)

      Logger.section("Second request — body")
      if let body = try await secondResult.request.body {
        Helpers.printJSON(body)
      } else {
        Logger.info("<none>")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func logReasoning(_ reasoning: [ReasoningOutput]) {
    if reasoning.isEmpty {
      Logger.info("<none>")
      return
    }
    for part in reasoning {
      Logger.info(part.text)
    }
  }
}
