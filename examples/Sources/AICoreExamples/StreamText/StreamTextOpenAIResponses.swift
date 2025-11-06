import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesExample: Example {
  static let name = "stream-text/openai-responses"
  static let description = "Stream text using the OpenAI Responses API."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai.responses(modelId: "gpt-4.1-mini"),
        prompt: "List three quick tips for writing testable Swift code."
      )

      Logger.section("Streamed output")
      for try await delta in result.textStream {
        print(delta, terminator: "")
      }
      print("")

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
