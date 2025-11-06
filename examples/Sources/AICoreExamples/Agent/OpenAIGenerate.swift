import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIGenerateExample: Example {
  static let name = "agent/openai-generate"
  static let description = "Non-streaming agent generate; prints content summary."

  static func run() async throws {
    do {
      let model = try openai("gpt-4o")
      let settings = BasicAgentSettings(
        system: "You are a helpful assistant.",
        model: model
      )
      let agent = BasicAgent(settings: settings)
      let result = try await agent.generate(prompt: Prompt.text(
        "Invent a new holiday and describe its traditions."
      ))

      Logger.section("CONTENT:")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
