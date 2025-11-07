import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIAudioExample: Example {
  static let name = "generate-text/openai-audio"
  static let description = "Transcribe an audio attachment with GPT-4o audio preview."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let audioData = try loadAudioData()

      let messages: [ModelMessage] = [
        .user(
          UserModelMessage(
            content: .parts([
              .text(TextPart(text: "What is the audio saying?")),
              .file(
                FilePart(
                  data: .data(audioData),
                  mediaType: "audio/mpeg",
                  filename: "galileo.mp3"
                )
              )
            ])
          )
        )
      ]

      let result = try await generateText(
        model: openai.chat("gpt-4o-audio-preview"),
        messages: messages
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func loadAudioData() throws -> Data {
    let fm = FileManager.default
    let baseURL = URL(fileURLWithPath: fm.currentDirectoryPath)
    let candidates = [
      baseURL.appendingPathComponent("Data/galileo.mp3"),
      baseURL.appendingPathComponent("examples/Data/galileo.mp3"),
      baseURL.appendingPathComponent("../Data/galileo.mp3"),
      baseURL.appendingPathComponent("../examples/Data/galileo.mp3")
    ]

    for candidate in candidates where fm.fileExists(atPath: candidate.path) {
      Logger.debug("Loading audio clip from: \(candidate.path)")
      return try Data(contentsOf: candidate)
    }

    throw NSError(
      domain: "GenerateTextOpenAIAudioExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "galileo.mp3 not found. Copy it from external/vercel-ai-sdk/examples/ai-core/data to examples/Data."
      ]
    )
  }
}
