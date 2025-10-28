import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIStructuredOutputsNameDescriptionExample: Example {
  static let name = "generate-object/openai-structured-outputs-name-description"
  static let description = "Adds schema name and description for OpenAI structured outputs."

  struct Ingredient: Codable, Sendable {
    let name: String
    let amount: String
  }

  struct Recipe: Codable, Sendable {
    let name: String
    let ingredients: [Ingredient]
    let steps: [String]
  }

  static func run() async throws {
    do {
      let result = try await generateObject(
        model: openai("gpt-4o"),
        schema: Recipe.self,
        prompt: "Generate a lasagna recipe.",
        schemaName: "recipe",
        schemaDescription: "A recipe for lasagna."
      )

      Logger.section("Recipe")
      Helpers.printJSON(result.object)

      Logger.section("Token usage")
      Helpers.printJSON(result.usage)

      Logger.section("Finish reason")
      Logger.info(result.finishReason.rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
