/**
 Generate Object Example

 Demonstrates structured data generation with schemas.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/generating-structured-data.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProviderUtils
import ExamplesCore

@main
struct GenerateObjectExample: CLIExample {
  static let name = "Generate Structured Objects"
  static let description = "Generate typed, validated JSON objects"

  static func run() async throws {
    Logger.info("Defining recipe schema...")

    // Define a schema for a recipe
    let recipeSchema = FlexibleSchema(jsonSchema(
      .object([
        "type": .string("object"),
        "properties": .object([
          "name": .object(["type": .string("string")]),
          "ingredients": .object([
            "type": .string("array"),
            "items": .object([
              "type": .string("object"),
              "properties": .object([
                "name": .object(["type": .string("string")]),
                "amount": .object(["type": .string("string")])
              ]),
              "required": .array([.string("name"), .string("amount")])
            ])
          ]),
          "steps": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
          ])
        ]),
        "required": .array([.string("name"), .string("ingredients"), .string("steps")])
      ])
    ))

    Logger.info("Generating structured recipe...")

    // Generate object
    let result = try await generateObject(
      model: openai("gpt-4o"),
      schema: recipeSchema,
      prompt: "Generate a lasagna recipe.",
      schemaName: "recipe",
      schemaDescription: "A recipe for lasagna."
    )

    // Display result
    Logger.section("Generated Recipe")
    Helpers.printJSON(result.object)

    Logger.separator()
    Logger.info("Tokens used: \(result.usage.totalTokens ?? 0)")
    Logger.info("Finish reason: \(result.finishReason)")
  }
}
