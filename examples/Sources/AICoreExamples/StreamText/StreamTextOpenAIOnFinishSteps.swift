import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnFinishStepsExample: Example {
  static let name = "stream-text/openai-on-finish-steps"
  static let description = "Inspect each step in onEnd (finishReason/usage/text)."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "Give me a 3-step plan to learn Swift.",
        stopWhen: [isStepCount(3)],
        onEnd: { event in
          Logger.section("steps summary")
          for (i, step) in event.steps.enumerated() {
            Logger.info("#\(i+1) reason=\(step.finishReason) tokens=\(step.usage.totalTokens ?? 0)")
            Logger.info(Helpers.truncate(step.text, to: 160))
          }
        }
      )
      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

