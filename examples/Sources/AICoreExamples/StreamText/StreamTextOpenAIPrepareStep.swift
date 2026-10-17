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
        stopWhen: [isStepCount(2)],
        prepareStep: { options in
          Logger.info("prepareStep: step=\(options.stepNumber) toolChoice=none")
          return PrepareStepResult(
            toolChoice: ToolChoice.none,
            instructions: "Be concise.",
            maxOutputTokens: 100
          )
        },
        include: .init(requestBody: true),
        onEnd: { event in
          Logger.section("Finish")
          Logger.info("finishReason: \(event.finishReason)")
          Logger.info("totalTokens: \(event.totalUsage.totalTokens ?? 0)")
        },
        onStepEnd: { step in
          Logger.info("step finish: reason=\(step.finishReason) tokens=\(step.usage.totalTokens ?? 0)")
          Logger.info("request body: \(String(describing: step.request.body))")
        }
      )

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
