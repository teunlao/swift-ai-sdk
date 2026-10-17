import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnFinishExample: Example {
  static let name = "stream-text/openai-on-finish"
  static let description = "Use onEnd to inspect the final step, steps and usage."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-5-mini"),
        prompt: "Invent a two-line poem about vectors.",
        onEnd: { event in
          Logger.section("onEnd")
          Logger.info("finishReason=\(event.finishReason)")
          Logger.info("steps=\(event.steps.count)")
          Logger.section("finalStep.text")
          Logger.info(Helpers.truncate(event.finalStep.text, to: 200))
          Logger.section("usage")
          Helpers.printJSON(event.totalUsage)
        }
      )

      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
