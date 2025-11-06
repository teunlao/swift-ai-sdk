import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIImageGenerationToolExample: Example {
  static let name = "stream-text/openai-image-generation-tool"
  static let description = "Use OpenAI imageGeneration tool during streaming; log tool calls/results."

  static func run() async throws {
    do {
      let imageTool = openai.tools.imageGeneration()

      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Create a simple monochrome sketch of a paper airplane using the image_generation tool, then describe it in one sentence.",
        tools: ["image_generation": imageTool]
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

