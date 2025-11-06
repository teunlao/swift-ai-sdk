import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIWebSearchToolExample: Example {
  static let name = "stream-text/openai-web-search-tool"
  static let description = "Use OpenAI webSearch tool during streaming; log tool calls/results."

  static func run() async throws {
    do {
      let web = openai.tools.webSearch(OpenAIWebSearchArgs(
        searchContextSize: "low",
        userLocation: .init(country: "US", city: "San Francisco", region: "CA")
      ))

      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Find 2 recent Swift language updates and summarize in one paragraph.",
        tools: ["web_search": web]
      )

      for try await part in result.fullStream {
        switch part {
        case .toolCall(let call):
          Logger.info("toolCall: \(call.toolName) id=\(call.toolCallId)")
        case .toolResult(let res):
          Logger.info("toolResult: \(res.toolName) prelim=\(res.preliminary ?? false)")
        case .textDelta(_, let delta, _):
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

