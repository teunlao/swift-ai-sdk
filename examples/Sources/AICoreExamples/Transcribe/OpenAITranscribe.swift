import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct TranscribeOpenAIExample: Example {
  static let name = "transcribe/openai"
  static let description = "Basic speech-to-text using the whisper-1 model."

  static func run() async throws {
    let audioData = try loadAudio()

    let result = try await transcribe(
      model: openai.transcription("whisper-1"),
      audio: .data(audioData)
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
    Logger.info("Responses: \(result.responses)")
    Logger.info("Provider Metadata: \(result.providerMetadata)")
  }

  private static func loadAudio() throws -> Data {
    let fm = FileManager.default
    let baseURL = URL(fileURLWithPath: fm.currentDirectoryPath)
    let candidates = [
      baseURL.appendingPathComponent("Data/galileo.mp3"),
      baseURL.appendingPathComponent("examples/Data/galileo.mp3"),
      baseURL.appendingPathComponent("../Data/galileo.mp3"),
      baseURL.appendingPathComponent("../examples/Data/galileo.mp3")
    ]

    for candidate in candidates where fm.fileExists(atPath: candidate.path) {
      return try Data(contentsOf: candidate)
    }

    throw NSError(
      domain: "TranscribeOpenAIExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "galileo.mp3 not found. Place the file at examples/Data/galileo.mp3."
      ]
    )
  }
}
