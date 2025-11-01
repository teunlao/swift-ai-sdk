import ExamplesCore
import Foundation
import DeepgramProvider
import SwiftAISDK

struct TranscribeDeepgramExample: Example {
  static let name = "transcribe/deepgram"
  static let description = "Speech-to-text using Deepgram's nova-3 model."

  static func run() async throws {
    let audioData = try loadAudio()

    let result = try await transcribe(
      model: deepgram.transcription(modelId: "nova-3"),
      audio: .data(audioData)
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
    Logger.info("Responses: \(result.responses)")
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
      domain: "TranscribeDeepgramExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "galileo.mp3 not found. Place the file at examples/Data/galileo.mp3."
      ]
    )
  }
}
