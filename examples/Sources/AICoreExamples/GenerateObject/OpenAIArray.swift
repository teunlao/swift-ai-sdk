import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIArrayExample: Example {
  static let name = "generate-object/openai-array"
  static let description = "Structured object array generation using OpenAI GPT-4o."

  struct Character: Codable, Sendable {
    let name: String
    let `class`: String
    let description: String
  }

  static func run() async throws {
    do {
      let result = try await generateObjectArray(
        model: openai("gpt-4o"),
        schema: Character.self,
        prompt: "Generate 3 hero descriptions for a fantasy role playing game."
      )

      Logger.section("Characters")
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
