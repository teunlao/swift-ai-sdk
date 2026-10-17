import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIStreamCallOptionsExample: Example {
  static let name = "agent/openai-stream-call-options"
  static let description = "Agent.stream with providerOptions (e.g., reasoningEffort)."

  static func run() async throws {
    do {
      let providerOptions: ProviderOptions = [
        "openai": [
          "reasoningEffort": "medium",
          "reasoningSummary": "detailed"
        ]
      ]

      let settings = ToolLoopAgentSettings<Never, String, String>(
        instructions: "You are a helpful assistant.",
        model: .v4(try openai("gpt-5-mini")),
        onStepEnd: { step in
          Logger.section("Step finished")
          Logger.info("finishReason=\(step.finishReason) tokens=\(step.usage.totalTokens ?? 0)")
        },
        providerOptions: providerOptions
      )

      let agent = ToolLoopAgent(settings)
      let result = try await agent.stream(prompt: "Summarize yesterday's top 3 tech headlines.")
      for try await d in result.textStream { print(d, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
