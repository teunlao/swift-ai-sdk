import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIExample: Example {
  static let name = "generate-text/openai"
  static let description = "Basic text generation using OpenAI's GPT-5 mini model."

  static func run() async throws {
    let result = try await generateText(
      model: openai("gpt-5-mini"),
      prompt: "Invent a new holiday and describe its traditions."
    )

    Logger.section("Generated Text")
    Logger.info(result.text)

    Logger.section("Usage")
    Helpers.printJSON(result.usage)
  }
}
