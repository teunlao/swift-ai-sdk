import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIFullResultExample: Example {
  static let name = "generate-object/openai-full-result"
  static let description = "Full generateObject result serialized to JSON."

  struct Recipe: Codable, Sendable {
    struct Ingredient: Codable, Sendable {
      let name: String
      let amount: String
    }

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
        prompt: "Generate a lasagna recipe."
      )

      Logger.section("Full Result (JSON)")
      let json = try result.jsonString()
      print(json)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
