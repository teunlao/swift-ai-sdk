import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnChunkExample: Example {
  static let name = "stream-text/openai-on-chunk"
  static let description = "Use onChunk to observe streaming parts (text/tool/etc.)."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "List 3 programming languages and a fun fact about each.",
        onChunk: { part in
          Logger.info("chunk: \(String(describing: part))")
        }
      )

      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

