import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIGenerateOnFinishExample: Example {
  static let name = "agent/openai-generate-on-finish"
  static let description = "Agent.generate with onEnd callback printing final text."

  static func run() async throws {
    do {
      let settings = ToolLoopAgentSettings<Never, String, String>(
        instructions: "You are a helpful assistant.",
        model: try openai("gpt-4o"),
        onEnd: { event in
          Logger.section("onEnd")
          Logger.info(event.text)
        }
      )
      let agent = ToolLoopAgent(settings)
      _ = try await agent.generate(prompt: "Invent a new holiday and describe its traditions.")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

