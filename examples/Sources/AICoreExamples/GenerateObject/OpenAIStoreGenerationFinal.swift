import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIStoreGenerationFinalExample: Example {
  static let name = "generate-object/openai-store-generation"
  static let description = "Stores responses on OpenAI while returning a structured object."

  struct Ingredient: Codable, Sendable {
    let name: String
    let amount: String
  }

  struct Recipe: Codable, Sendable {
    let name: String
    let ingredients: [Ingredient]
    let steps: [String]
  }

  struct Response: Codable, Sendable {
    let recipe: Recipe
  }

  static func run() async throws {
    do {
      let result = try await generateObject(
        model: openai("gpt-4o-mini"),
        schema: Response.self,
        prompt: "Generate a lasagna recipe as JSON matching the schema.",
        mode: .json,
        providerOptions: [
          "openai": [
            "store": .bool(true),
            "metadata": .object(["custom": .string("value")])
          ]
        ]
      )

      Logger.section("Recipe")
      Helpers.printJSON(result.object.recipe)

      Logger.section("Token usage")
      Helpers.printJSON(result.usage)

      Logger.section("Finish reason")
      Logger.info(result.finishReason.rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
