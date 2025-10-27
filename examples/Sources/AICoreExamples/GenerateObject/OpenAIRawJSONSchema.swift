import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIRawJSONSchemaExample: Example {
  static let name = "generate-object/openai-raw-json-schema"
  static let description = "Defines a manual JSON Schema for recipe generation using OpenAI GPT-4o."

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
    // Mirrors the TypeScript example: hand-authored JSON Schema instead of auto(Codable).
    let recipeSchemaJSON: JSONValue = [
      "type": "object",
      "properties": [
        "recipe": [
          "type": "object",
          "properties": [
            "name": ["type": "string"],
            "ingredients": [
              "type": "array",
              "items": [
                "type": "object",
                "properties": [
                  "name": ["type": "string"],
                  "amount": ["type": "string"]
                ],
                "required": ["name", "amount"]
              ]
            ],
            "steps": [
              "type": "array",
              "items": ["type": "string"]
            ]
          ],
          "required": ["name", "ingredients", "steps"]
        ]
      ],
      "required": ["recipe"]
    ]

    let schema = FlexibleSchema<Response>.jsonSchema(recipeSchemaJSON)

    do {
      let result = try await generateObject(
        model: openai("gpt-4o"),
        schema: schema,
        prompt: "Generate a lasagna recipe.",
        mode: .json
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
