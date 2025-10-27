import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIReasoningExample: Example {
  static let name = "generate-object/openai-reasoning"
  static let description = "Requests reasoning traces and strict JSON from OpenAI GPT-5."

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
    let recipeSchemaJSON: JSONValue = [
      "type": "object",
      "additionalProperties": .bool(false),
      "properties": [
        "recipe": [
          "type": "object",
          "additionalProperties": .bool(false),
          "properties": [
            "name": ["type": "string"],
            "ingredients": [
              "type": "array",
              "items": [
                "type": "object",
                "additionalProperties": .bool(false),
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

    do {
      let result = try await generateObject(
        model: openai("gpt-5"),
        schema: FlexibleSchema<Response>.jsonSchema(recipeSchemaJSON),
        prompt: "Generate a lasagna recipe.",
        mode: .json,
        providerOptions: [
          "openai": [
            "strictJsonSchema": .bool(true),
            "reasoningSummary": .string("detailed")
          ]
        ]
      )

      if let reasoning = result.reasoning {
        Logger.section("Reasoning summary")
        Logger.info(reasoning)
      }

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
