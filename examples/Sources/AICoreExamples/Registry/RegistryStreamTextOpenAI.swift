import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct RegistryStreamTextOpenAIExample: Example {
  static let name = "registry/stream-text-openai"
  static let description = "Use ProviderRegistry to stream text via 'openai:modelId'."

  static func run() async throws {
    do {
      let registry = createProviderRegistry(providers: [
        "openai": createOpenAIProvider()
      ])

      let model = registry.languageModel(id: "openai:gpt-4o")
      let result = try streamText(
        model: model,
        prompt: "Say hello from the registry stream example."
      )

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
