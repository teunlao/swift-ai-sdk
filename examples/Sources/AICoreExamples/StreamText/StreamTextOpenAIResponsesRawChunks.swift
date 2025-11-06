import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesRawChunksExample: Example {
  static let name = "stream-text/openai-responses-raw-chunks"
  static let description = "Display raw provider chunks (.raw) when streaming with the OpenAI Responses API."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai.responses(modelId: "gpt-4o-mini"),
        prompt: "Name two features of this SDK in one sentence.",
        includeRawChunks: true
      )

      Logger.section("Raw parts")
      for try await part in result.fullStream {
        if case .raw(let raw) = part { Helpers.printJSON(raw) }
      }

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
