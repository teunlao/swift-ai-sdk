import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct RegistryTranscribeOpenAIExample: Example {
  static let name = "registry/transcribe-openai"
  static let description = "Transcribe audio via registry using openai:whisper-1."

  static func run() async throws {
    do {
      _ = createProviderRegistry(providers: ["openai": createOpenAIProvider()])
      let model = openai.transcription(modelId: "whisper-1")

      // Generate a small sample audio using TTS first (to avoid external files)
      let tts = try await generateSpeech(
        model: openai.speech("tts-1"),
        text: "Hello from the Swift AI SDK registry transcription demo."
      )
      let transcript = try await transcribe(model: model, audio: .data(tts.audio.data))
      Logger.section("Transcription")
      Logger.info(transcript.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
