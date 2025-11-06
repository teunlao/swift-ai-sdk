import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct AgentOpenAIGenerateCallOptionsExample: Example {
  static let name = "agent/openai-generate-call-options"
  static let description = "Agent.generate with providerOptions (OpenAI.strictJsonSchema) + Output.object."

  private struct Ingredient: Codable, Sendable { let name: String; let amount: String }
  private struct Recipe: Codable, Sendable { let name: String; let ingredients: [Ingredient]; let steps: [String] }

  static func run() async throws {
    do {
      let outputSpec = Output.object(Recipe.self, name: "recipe", description: "Lasagna recipe")

      // Provider options: enable strict JSON schema enforcement for OpenAI responses
      let providerOptions: ProviderOptions = [
        "openai": ["strictJsonSchema": true]
      ]

      let settings = AgentSettings<Recipe, JSONValue>(
        system: "You are a helpful assistant.",
        model: try openai("gpt-4o"),
        experimentalOutput: outputSpec,
        providerOptions: providerOptions
      )

      let agent = Agent(settings: settings)
      let result = try await agent.generate(prompt: Prompt.text("Generate a lasagna recipe."))
      let recipe = try result.experimentalOutput
      Logger.section("Strict JSON parsed")
      Logger.info("Recipe: \(recipe.name) (\(recipe.ingredients.count) ingredients)")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

