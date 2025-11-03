import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIAudioExample: Example {
  static let name = "stream-text/openai-audio"
  static let description = "Stream text with an audio file input (gpt-4o-audio-preview)."

  static func run() async throws {
    do {
      let audioData = try loadAudio()

      let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
        model: openai("gpt-4o-audio-preview"),
        system: nil,
        messages: [
          .user(UserModelMessage(
            content: .parts([
              .text(TextPart(text: "What is the audio saying?")),
              .file(FilePart(data: .data(audioData), mediaType: "audio/mpeg"))
            ])
          ))
        ]
      )

      for try await delta in result.textStream {
        print(delta, terminator: "")
      }
      print("")

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)

      Logger.section("Finish Reason")
      Logger.info(String(describing: try await result.finishReason))
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func loadAudio() throws -> Data {
    let fm = FileManager.default
    let base = URL(fileURLWithPath: fm.currentDirectoryPath)
    let candidates = [
      base.appendingPathComponent("Data/galileo.mp3"),
      base.appendingPathComponent("examples/Data/galileo.mp3"),
      base.appendingPathComponent("../Data/galileo.mp3"),
      base.appendingPathComponent("../examples/Data/galileo.mp3")
    ]
    for url in candidates where fm.fileExists(atPath: url.path) { return try Data(contentsOf: url) }
    throw NSError(domain: name, code: 1, userInfo: [NSLocalizedDescriptionKey: "galileo.mp3 not found. Place it at examples/Data/galileo.mp3."])
  }
}
