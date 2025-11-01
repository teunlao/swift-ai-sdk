import ExamplesCore
import Foundation
import DeepgramProvider
import SwiftAISDK

struct TranscribeDeepgramURLExample: Example {
  static let name = "transcribe/deepgram-url"
  static let description = "Deepgram nova-3 transcription using audio fetched from this repository."

  static func run() async throws {
    guard let audioURL = URL(string: "https://raw.githubusercontent.com/teunlao/swift-ai-sdk/main/examples/Data/galileo.mp3") else {
      throw NSError(domain: "TranscribeDeepgramURLExample", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL."])
    }

    let result = try await transcribe(
      model: deepgram.transcription(modelId: "nova-3"),
      audio: .url(audioURL)
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
    Logger.info("Responses: \(result.responses)")
  }
}
