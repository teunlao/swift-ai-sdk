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

@main
struct GenerateObjectExample: CLIExample {
  static let name = "Generate Structured Objects"
  static let description = "Generate typed, validated JSON objects"

  static func run() async throws {
    try EnvLoader.load()

    Logger.section("Generating structured recipe")

    let result = try await generateObject(
      model: openai("gpt-4o"),
      schema: Recipe.self,
      prompt: "Generate a lasagna recipe.",
      schemaName: "recipe",
      schemaDescription: "A recipe for lasagna."
    ).object

    Logger.info("Recipe: \(result.name)")
    Logger.info("Ingredients:")
    for ingredient in result.ingredients {
      Logger.info("- \(ingredient.amount) \(ingredient.name)")
    }

    Logger.info("Steps:")
    for (index, step) in result.steps.enumerated() {
      Logger.info("\(index + 1). \(step)")
    }
  }
}
