import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct AgentOpenAIGenerateJSONExample: Example {
  static let name = "agent/openai-generate-json"
  static let description = "Agent.generate with Output.object schema (structured JSON)."

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
      let result = try await agent.generate(prompt: "Generate a lasagna recipe.")

      Logger.section("Structured Output")
      let recipe = try result.output
      Logger.info("Recipe: \(recipe.name)")
      for ing in recipe.ingredients.prefix(3) { Logger.info("- \(ing.amount) \(ing.name)") }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

