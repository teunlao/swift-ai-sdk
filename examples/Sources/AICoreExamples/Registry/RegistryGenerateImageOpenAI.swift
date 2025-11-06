import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct RegistryGenerateImageOpenAIExample: Example {
  static let name = "registry/generate-image"
  static let description = "Generate an image via registry using openai:gpt-image-1-mini."

  static func run() async throws {
    do {
      let registry = createProviderRegistry(providers: [
        "openai": createOpenAIProvider()
      ])

      let model = registry.imageModel(id: "openai:gpt-image-1-mini")
      let result = try await generateImage(
        model: model,
        prompt: "A simple sketch of a paper airplane, monochrome"
      )

      Logger.section("Image generated")
      Logger.info("mediaType: \(result.image.mediaType)")
      Logger.info("bytes: \(result.image.data.count)")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
