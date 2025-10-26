import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIEnumExample: Example {
  static let name = "generate-object/openai-enum"
  static let description = "Classifies text into an enum using OpenAI GPT-4o mini."

  static func run() async throws {
    do {
      let result = try await generateObjectEnum(
        model: openai("gpt-4o-mini"),
        values: ["action", "comedy", "drama", "horror", "sci-fi"],
        prompt: "Classify the genre of this movie plot: \"A group of astronauts travel through a wormhole in search of a new habitable planet for humanity.\""
      )

      Logger.section("Predicted genre")
      Logger.info(result.object)

      Logger.section("Token usage")
      Helpers.printJSON(result.usage)

      Logger.section("Finish reason")
      Logger.info(result.finishReason.rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
