import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIFullstreamLogprobsExample: Example {
  static let name = "stream-text/openai-fullstream-logprobs"
  static let description = "Enable OpenAI logprobs via providerOptions and observe in stream."

  static func run() async throws {
    do {
      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Write a short pangram.",
        providerOptions: ["openai": ["logprobs": 2]],
        includeRawChunks: false
      )

      for try await part in result.fullStream {
        switch part {
        case .textDelta(_, let delta, let meta):
          if meta != nil { Logger.info("(logprobs metadata present)") }
          print(delta, terminator: "")
        default:
          break
        }
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

