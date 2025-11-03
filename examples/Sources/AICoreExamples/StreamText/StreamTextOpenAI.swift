import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIExample: Example {
  static let name = "stream-text/openai"
  static let description = "Basic text streaming with OpenAI gpt-5-mini and onFinish."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-5-mini"),
        prompt: "Invent a new holiday and describe its traditions.",
        onFinish: { finalStep, steps, totalUsage, finishReason in
          Logger.section("Finish")
          Logger.info("finishReason: \(finishReason)")
          Logger.section("Usage")
          Helpers.printJSON(totalUsage)
        }
      )

      Logger.section("Streamed Output")
      for try await delta in result.textStream {
        print(delta, terminator: "")
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
