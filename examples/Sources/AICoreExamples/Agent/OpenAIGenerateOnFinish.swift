import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIGenerateOnFinishExample: Example {
  static let name = "agent/openai-generate-on-finish"
  static let description = "Agent.generate with onFinish callback printing final text."

  static func run() async throws {
    do {
      let settings = BasicAgentSettings(
        system: "You are a helpful assistant.",
        model: try openai("gpt-4o"),
        onFinish: { event in
          Logger.section("onFinish")
          Logger.info(event.text)
        }
      )
      let agent = BasicAgent(settings: settings)
      _ = try await agent.generate(prompt: Prompt.text("Invent a new holiday and describe its traditions."))
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

