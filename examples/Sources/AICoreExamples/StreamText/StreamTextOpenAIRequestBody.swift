import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIRequestBodyExample: Example {
  static let name = "stream-text/openai-request-body"
  static let description = "Inspect the JSON request body sent to OpenAI during streamText."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "Say one short sentence about structured outputs."
      )

      // Consume the stream so the request metadata is populated.
      for try await _ in result.textStream { }

      Logger.section("Request body (JSON)")
      let req = try await result.request
      if let body = req.body {
        Helpers.printJSON(body)
      } else {
        Logger.warning("Request body is unavailable for this provider/model.")
      }

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
