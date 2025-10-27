import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIResponsesExample: Example {
  static let name = "generate-object/openai-responses"
  static let description = "Calls the OpenAI responses API with json mode."

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
        model: openai.responses(modelId: "gpt-4o-mini"),
        schema: Response.self,
        prompt: "Generate a lasagna recipe.",
        schemaName: "recipe",
        schemaDescription: "Generate a lasagna recipe."
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
