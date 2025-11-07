import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesServiceTierExample: Example {
  static let name = "stream-text/openai-responses-service-tier"
  static let description = "OpenAI Responses API with the serviceTier provider option."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai.responses("gpt-4.1-mini"),
        prompt: "Briefly describe what service tiers do.",
        providerOptions: openai.options.responses(serviceTier: "auto")
      )

      for try await _ in result.textStream { }

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
