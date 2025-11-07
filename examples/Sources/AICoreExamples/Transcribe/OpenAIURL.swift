import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct TranscribeOpenAIURLExample: Example {
  static let name = "transcribe/openai-url"
  static let description = "Speech-to-text using whisper-1 with audio fetched from a remote URL."

  static func run() async throws {
    guard let audioURL = URL(string: "https://raw.githubusercontent.com/teunlao/swift-ai-sdk/main/examples/Data/galileo.mp3") else {
      throw NSError(domain: "TranscribeOpenAIURLExample", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL."])
    }

    let result = try await transcribe(
      model: openai.transcription("whisper-1"),
      audio: .url(audioURL)
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
    Logger.info("Responses: \(result.responses)")
    Logger.info("Provider Metadata: \(result.providerMetadata)")
  }
}
