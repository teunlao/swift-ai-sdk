import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct StreamTextOpenAIPrepareStepExample: Example {
  static let name = "stream-text/openai-prepare-step"
  static let description = "Use prepareStep to tweak step settings and inspect the request."

  static func run() async throws {
    do {
      Logger.section("prepareStep demo")

      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "In 1 sentence explain why Swift is good for iOS.",
        prepareStep: { options in
          // Example: enforce toolChoice and add a system hint for step >= 2
          var result = PrepareStepResult()
          if options.stepNumber >= 2 {
            result.system = "Be concise."
          }
          result.toolChoice = ToolChoice.none
          Logger.info("prepareStep: step=\(options.stepNumber) toolChoice=none")
          return result
        },
        stopWhen: [stepCountIs(2)],
        onStepFinish: { step in
          Logger.info("step finish: reason=\(step.finishReason) tokens=\(step.usage.totalTokens ?? 0)")
        },
        onFinish: { _, _, usage, reason in
          Logger.section("Finish")
          Logger.info("finishReason: \(reason)")
          Logger.info("totalTokens: \(usage.totalTokens ?? 0)")
        }
      )

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
