import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct RegistryEmbedOpenAIExample: Example {
  static let name = "registry/embed-openai"
  static let description = "Create embeddings through ProviderRegistry using openai:text-embedding-3-small."

  static func run() async throws {
    do {
      let registry = createProviderRegistry(providers: [
        "openai": createOpenAIProvider()
      ])

      let model = registry.textEmbeddingModel(id: "openai:text-embedding-3-small")
      let text = "sunny day at the beach"
      let result = try await embed(model: model, value: text)
      Logger.section("Embedding (first 8 dims)")
      Logger.info(result.embedding.prefix(8).map { String(format: "%.5f", $0) }.joined(separator: ", "))
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
