import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIStreamExample: Example {
  static let name = "agent/openai-stream"
  static let description = "Stream agent output with a simple prompt."

  static func run() async throws {
    do {
      let model = try openai("gpt-5")
      let settings = ToolLoopAgentSettings<Never, String, String>(
        instructions: "You are a helpful assistant.",
        model: model
      )
      let agent = ToolLoopAgent(settings)

      let result = try await agent.stream(
        prompt: "Invent a new holiday and describe its traditions."
      )

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
