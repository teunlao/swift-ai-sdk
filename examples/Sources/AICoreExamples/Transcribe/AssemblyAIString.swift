import ExamplesCore
import Foundation
import AssemblyAIProvider
import SwiftAISDK

struct TranscribeAssemblyAIStringExample: Example {
  static let name = "transcribe/assemblyai-string"
  static let description = "AssemblyAI transcription with base64 audio input."

  static func run() async throws {
    let base64Audio = try loadAudioBase64()

    let result = try await transcribe(
      model: assemblyai.transcription(modelId: "best"),
      audio: .base64(base64Audio)
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
    Logger.info("Responses: \(result.responses)")
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
      domain: "TranscribeAssemblyAIStringExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "galileo.mp3 not found. Place the file at examples/Data/galileo.mp3."
      ]
    )
  }
}
