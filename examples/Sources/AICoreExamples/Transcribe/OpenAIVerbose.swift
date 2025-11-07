import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct TranscribeOpenAIVerboseExample: Example {
  static let name = "transcribe/openai-verbose"
  static let description = "Speech-to-text using whisper-1 with provider options for timestamp granularity." 

  static func run() async throws {
    let audioData = try loadAudio()

    let providerOptions: ProviderOptions = [
      "openai": [
        "timestampGranularities": .array([.string("segment")])
      ]
    ]

    let result = try await transcribe(
      model: openai.transcription("whisper-1"),
      audio: .data(audioData),
      providerOptions: providerOptions
    )

    Logger.info("Text: \(result.text)")
    Logger.info("Duration: \(result.durationInSeconds?.description ?? "nil")")
    Logger.info("Language: \(result.language ?? "nil")")
    Logger.info("Segments: \(result.segments)")
    Logger.info("Warnings: \(result.warnings)")
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
      domain: "TranscribeOpenAIVerboseExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "galileo.mp3 not found. Place the file at examples/Data/galileo.mp3."
      ]
    )
  }
}
