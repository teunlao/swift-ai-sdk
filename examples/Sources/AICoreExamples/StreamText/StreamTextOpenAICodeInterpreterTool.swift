import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAICodeInterpreterToolExample: Example {
  static let name = "stream-text/openai-code-interpreter-tool"
  static let description = "Use OpenAI codeInterpreter tool during streaming; log outputs."

  static func run() async throws {
    do {
      let codeTool = openai.tools.codeInterpreter()

      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Use the code interpreter to compute the first 5 squares and print them as a JSON array.",
        tools: ["code_interpreter": codeTool]
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

