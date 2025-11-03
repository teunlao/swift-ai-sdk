import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateSpeechOpenAIExample: Example {
  static let name = "generate-speech/openai"
  static let description = "Generate speech audio with OpenAI tts-1 and save to a file."

  static func run() async throws {
    do {
      let result = try await generateSpeech(
        model: openai.speech("tts-1"),
        text: "Hello from the AI SDK!",
        voice: "alloy"
      )

      Logger.section("Warnings")
      if result.warnings.isEmpty {
        Logger.info("none")
      } else {
        Helpers.printJSON(result.warnings.map { String(describing: $0) })
      }

      let ext: String = {
        switch result.audio.mediaType.lowercased() {
        case "audio/mp3": return "mp3"
        case "audio/wav": return "wav"
        case "audio/flac": return "flac"
        case "audio/ogg", "audio/opus": return "opus"
        default: return "mp3"
        }
      }()
      let fileURL = try Helpers.createTempFile(data: result.audio.data, extension: ext)
      Logger.success("Saved → \(fileURL.path)")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

