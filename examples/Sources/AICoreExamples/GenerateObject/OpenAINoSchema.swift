import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAINoSchemaExample: Example {
  static let name = "generate-object/openai-no-schema"
  static let description = "Generates JSON without a schema using OpenAI GPT-4o."

  static func run() async throws {
    do {
      let result = try await generateObjectNoSchema(
        model: openai("gpt-4o"),
        prompt: "Generate a lasagna recipe as JSON."
      )

      Logger.section("JSON payload")
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
