import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIGenerateExample: Example {
  static let name = "agent/openai-generate"
  static let description = "Non-streaming agent generate; prints content summary."

  static func run() async throws {
    do {
      let model = try openai("gpt-4o")
      let settings = ToolLoopAgentSettings<Never, String, String>(
        instructions: "You are a helpful assistant.",
        model: model
      )
      let agent = ToolLoopAgent(settings)
      let result = try await agent.generate(
        prompt: "Invent a new holiday and describe its traditions."
      )

      Logger.section("CONTENT:")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
