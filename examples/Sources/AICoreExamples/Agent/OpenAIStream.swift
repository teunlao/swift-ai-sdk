import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIStreamExample: Example {
  static let name = "agent/openai-stream"
  static let description = "Stream agent output with a simple prompt."

  static func run() async throws {
    do {
      let model = try openai("gpt-5")
      let settings = BasicAgentSettings(
        system: "You are a helpful assistant.",
        model: model
      )
      let agent = BasicAgent(settings: settings)

      let result = try agent.stream(prompt: Prompt.text(
        "Invent a new holiday and describe its traditions."
      ))

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
