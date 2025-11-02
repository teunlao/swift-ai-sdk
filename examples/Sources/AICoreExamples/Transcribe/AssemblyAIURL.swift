import ExamplesCore
import Foundation
import AssemblyAIProvider
import SwiftAISDK

struct TranscribeAssemblyAIURLExample: Example {
  static let name = "transcribe/assemblyai-url"
  static let description = "AssemblyAI transcription using remote audio from this repository."

  static func run() async throws {
    guard let audioURL = URL(string: "https://raw.githubusercontent.com/teunlao/swift-ai-sdk/main/examples/Data/galileo.mp3") else {
      throw NSError(domain: "TranscribeAssemblyAIURLExample", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL."])
    }

    let result = try await transcribe(
      model: assemblyai.transcription(modelId: "best"),
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
