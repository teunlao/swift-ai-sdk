/**
 Generate Object Example

 Demonstrates structured data generation with schemas.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/generating-structured-data.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

struct Ingredient: Codable, Sendable {
  let name: String
  let amount: String
}

struct Recipe: Codable, Sendable {
  let name: String
  let ingredients: [Ingredient]
  let steps: [String]
}

struct RecipeResponse: Codable, Sendable {
  let recipe: Recipe
}

@main
struct GenerateObjectExample: CLIExample {
  static let name = "Generate Structured Objects"
  static let description = "Generate typed, validated JSON objects"

  static func run() async throws {
    try EnvLoader.load()

    Logger.section("Generating structured recipe")

    let response = try await generateObject(
      model: openai("gpt-4o"),
      schema: RecipeResponse.self,
      prompt: "Generate a lasagna recipe.",
      schemaName: "recipe_response",
      schemaDescription: "Structured lasagna recipe response."
    ).object

    let recipe = response.recipe
    Logger.info("Recipe: \(recipe.name)")

    Logger.info("Ingredients:")
    for ingredient in recipe.ingredients {
      Logger.info("- \(ingredient.amount) \(ingredient.name)")
    }

    Logger.info("Steps:")
    for (index, step) in recipe.steps.enumerated() {
      Logger.info("\(index + 1). \(step)")
    }
  }
}
