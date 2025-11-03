import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnFinishExample: Example {
  static let name = "stream-text/openai-on-finish"
  static let description = "Use onFinish to inspect the final step, steps and usage."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-5-mini"),
        prompt: "Invent a two-line poem about vectors.",
        onFinish: { finalStep, steps, totalUsage, finishReason in
          Logger.section("onFinish")
          Logger.info("finishReason=\(finishReason)")
          Logger.info("steps=\(steps.count)")
          Logger.section("finalStep.text")
          Logger.info(Helpers.truncate(finalStep.text, to: 200))
          Logger.section("usage")
          Helpers.printJSON(totalUsage)
        }
      )

      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
