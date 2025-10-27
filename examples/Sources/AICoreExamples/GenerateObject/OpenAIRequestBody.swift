import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIRequestBodyExample: Example {
  static let name = "generate-object/openai-request-body"
  static let description = "Inspects the JSON request body sent to OpenAI."

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
        prompt: "Generate a lasagna recipe."
      )

      Logger.section("Request body")
      if let body = result.request.body {
        Helpers.printJSON(body)
      } else {
        Logger.info("Request body unavailable")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
