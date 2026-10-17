import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct AgentOpenAIStreamJSONExample: Example {
  static let name = "agent/openai-stream-json"
  static let description = "Agent.stream with Output.object schema and partial JSON stream."

  private struct Ingredient: Codable, Sendable { let name: String; let amount: String }
  private struct Recipe: Codable, Sendable { let name: String; let ingredients: [Ingredient]; let steps: [String] }

  static func run() async throws {
    do {
      let outputSpec = Output.object(Recipe.self, name: "recipe", description: "Lasagna recipe")
      let settings = ToolLoopAgentSettings<Never, Recipe, JSONValue>(
        instructions: "You are a helpful assistant.",
        model: try openai("gpt-4o"),
        output: outputSpec
      )
      let agent = ToolLoopAgent(settings)
      let result = try await agent.stream(prompt: "Generate a lasagna recipe.")

      Logger.section("Partial JSON stream (first 3 events)")
      var count = 0
      for try await partial in result.partialOutputStream {
        Logger.info(String(describing: partial))
        count += 1
        if count >= 3 { break }
      }

      // Drain text stream to completion
      for try await _ in result.textStream { }

      do {
        let recipe = try await result.output
        Logger.section("Parsed Output")
        Logger.info("Recipe: \(recipe.name)")
      } catch {
        Logger.warning("No structured output parsed: \(error.localizedDescription)")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

