import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct TranscribeOpenAIStringExample: Example {
  static let name = "transcribe/openai-string"
  static let description = "Speech-to-text using whisper-1 with base64 audio input."

  static func run() async throws {
    let base64Audio = try loadAudioBase64()

    let result = try await transcribe(
      model: openai.transcription(modelId: "whisper-1"),
      audio: .base64(base64Audio)
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
    Logger.info("Responses: \(result.responses)")
    Logger.info("Provider Metadata: \(result.providerMetadata)")
  }

  private static func loadAudioBase64() throws -> String {
    let fm = FileManager.default
    let baseURL = URL(fileURLWithPath: fm.currentDirectoryPath)
    let candidates = [
      baseURL.appendingPathComponent("Data/galileo.mp3"),
      baseURL.appendingPathComponent("examples/Data/galileo.mp3"),
      baseURL.appendingPathComponent("../Data/galileo.mp3"),
      baseURL.appendingPathComponent("../examples/Data/galileo.mp3")
    ]

    for candidate in candidates where fm.fileExists(atPath: candidate.path) {
      let data = try Data(contentsOf: candidate)
      return data.base64EncodedString()
    }

    throw NSError(
      domain: "TranscribeOpenAIStringExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "galileo.mp3 not found. Place the file at examples/Data/galileo.mp3."
      ]
    )
  }
}
