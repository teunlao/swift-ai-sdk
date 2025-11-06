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
      let settings = AgentSettings<Recipe, JSONValue>(
        system: "You are a helpful assistant.",
        model: try openai("gpt-4o"),
        experimentalOutput: outputSpec
      )
      let agent = Agent(settings: settings)
      let result = try agent.stream(prompt: Prompt.text("Generate a lasagna recipe."))

      Logger.section("Partial JSON stream (first 3 events)")
      var count = 0
      for try await partial in result.experimentalPartialOutputStream {
        Logger.info(String(describing: partial))
        count += 1
        if count >= 3 { break }
      }

      // Drain text stream to completion
      for try await _ in result.textStream { }

      do {
        let recipe = try await result.experimentalOutput
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

