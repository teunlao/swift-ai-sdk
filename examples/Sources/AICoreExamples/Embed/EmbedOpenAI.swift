import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct EmbedOpenAIExample: Example {
  static let name = "embed/openai"
  static let description = "Text embedding using OpenAI (text-embedding-3-small)."

  static func run() async throws {
    do {
      let text = "sunny day at the beach"
      let result = try await embed(
        model: openai.embedding("text-embedding-3-small"),
        value: text
      )

      Logger.section("Input")
      Logger.info(text)

      Logger.section("Embedding (first 8 dims)")
      let prefix = result.embedding.prefix(8)
      Logger.info("[" + prefix.map { String(format: "%.5f", $0) }.joined(separator: ", ") + ", ...]")

      Logger.section("Usage")
      Helpers.printJSON(result.usage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
