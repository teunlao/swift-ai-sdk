import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAILocalShellToolExample: Example {
  static let name = "stream-text/openai-local-shell-tool"
  static let description = "Use OpenAI localShell tool (safe demo: print date)."

  static func run() async throws {
    do {
      let shell = openai.tools.localShell()
      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Use the local_shell tool to run 'date -u +%Y-%m-%dT%H:%M:%SZ' and print the result.",
        tools: ["local_shell": shell]
      )

      for try await part in result.fullStream {
        switch part {
        case .toolCall(let call):
          Logger.info("toolCall: \(call.toolName) id=\(call.toolCallId)")
        case .toolResult(let res):
          Logger.info("toolResult: \(res.toolName) output=\(res.output)")
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

