import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct RegistryGenerateSpeechOpenAIExample: Example {
  static let name = "registry/generate-speech-openai"
  static let description = "Generate speech via registry using openai:tts-1."

  static func run() async throws {
    do {
      _ = createProviderRegistry(providers: ["openai": createOpenAIProvider()])
      // Speech via provider directly (registry speech access optional in current SDK)
      let model = openai.speech("tts-1")
      let audio = try await generateSpeech(
        model: model,
        text: "Swift AI SDK registry example generating speech."
      )
      Logger.section("Speech generated")
      Logger.info("bytes: \(audio.audio.data.count)")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
