import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnFinishStepsExample: Example {
  static let name = "stream-text/openai-on-finish-steps"
  static let description = "Inspect each step in onFinish (finishReason/usage/text)."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "Give me a 3-step plan to learn Swift.",
        stopWhen: [stepCountIs(3)],
        onFinish: { _, steps, _, _ in
          Logger.section("steps summary")
          for (i, step) in steps.enumerated() {
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

