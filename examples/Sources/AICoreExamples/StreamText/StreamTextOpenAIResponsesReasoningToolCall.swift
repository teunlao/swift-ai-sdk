import Foundation
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesReasoningToolCallExample: Example {
  static let name = "stream-text/openai-responses-reasoning-tool-call"
  static let description = "Stream reasoning/tool events with OpenAI Responses while retrying failed tools."

  private struct GenerateRandomTextInput: Codable, Sendable { let length: Int }
  private struct CountCharInput: Codable, Sendable { let text: String; let char: String }

  private enum ToolFailure: LocalizedError {
    case segmentationFault
    case bufferOverflow
    case invalidLength
    case invalidCharacter

    var errorDescription: String? {
      switch self {
      case .segmentationFault: return "Segmentation fault"
      case .bufferOverflow: return "Buffer overflow"
      case .invalidLength: return "Length must be at least 1"
      case .invalidCharacter: return "char must contain exactly one character"
      }
    }
  }

  static func run() async throws {
    do {
      let generateRandomText: TypedTool<GenerateRandomTextInput, String> = tool(
        description: "Generate a random text of a given length",
        inputSchema: .auto(GenerateRandomTextInput.self)
      ) { input, _ in
        guard input.length >= 1 else { throw ToolFailure.invalidLength }
        if Bool.random() { throw ToolFailure.segmentationFault }

        let letters = (0..<input.length).map { _ in
          String(UnicodeScalar(Int.random(in: 97...122))!)
        }
        return letters.joined()
      }

      let countChar: TypedTool<CountCharInput, Int> = tool(
        description: "Count occurrences of a character inside the text",
        inputSchema: .auto(CountCharInput.self)
      ) { input, _ in
        guard input.char.count == 1 else { throw ToolFailure.invalidCharacter }
        if Bool.random() { throw ToolFailure.bufferOverflow }

        let target = input.char.first!
        return input.text.reduce(0) { $1 == target ? $0 + 1 : $0 }
      }

      let providerOptions = openai.options.responses(
        store: false,
        reasoningEffort: "medium",
        reasoningSummary: "auto"
      )

      let result = try streamText(
        model: openai.responses("o3-mini"),
        system: "If you encounter a function call error, you should retry 3 times before giving up.",
        prompt: "Generate two texts of 1024 characters each. Count the number of \"a\" in the first text, and the number of \"b\" in the second text.",
        tools: [
          "generateRandomText": generateRandomText.tool,
          "countChar": countChar.tool
        ],
        providerOptions: providerOptions,
        stopWhen: [stepCountIs(10)]
      )

      for try await part in result.fullStream {
        switch part {
        case .start:
          Logger.info("START")

        case .startStep(let request, _):
          Logger.info("STEP START")
          if let body = request.body {
            Logger.info("Request body:")
            Helpers.printJSON(body)
          } else {
            Logger.info("Request body: <none>")
          }

        case .reasoningStart:
          print("\u{001B}[34m", terminator: "")
        case .reasoningDelta(_, let text, _):
          print(text, terminator: "")
        case .reasoningEnd:
          print("\u{001B}[0m")

        case .toolInputStart(_, let toolName, _, _, _):
          print("\u{001B}[33mTool call: \(toolName)")
          print("Tool args: ", terminator: "")
        case .toolInputDelta(_, let delta, _):
          print(delta, terminator: "")
        case .toolInputEnd:
          print("")

        case .toolResult(let result):
          print("Tool result: \(result.toolName)")
          Helpers.printJSON(result.output)
          print("\u{001B}[0m")

        case .toolError(let error):
          print("\u{001B}[31mTool error: \(error.toolName) -> \(error.error.localizedDescription)\u{001B}[0m")

        case .textStart:
          print("\u{001B}[32m", terminator: "")
        case .textDelta(_, let text, _):
          print(text, terminator: "")
        case .textEnd:
          print("\u{001B}[0m")

        case .finishStep(_, let usage, let finishReason, _):
          Logger.info("Finish reason: \(finishReason.rawValue)")
          Logger.info("Usage:")
          Helpers.printJSON(usage)
          Logger.info("STEP FINISH")

        case .finish(let finishReason, let totalUsage):
          Logger.info("Finish reason: \(finishReason.rawValue)")
          Logger.info("Total usage:")
          Helpers.printJSON(totalUsage)
          Logger.info("FINISH")

        case .error(let error):
          print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")

        default:
          break
        }
      }

      Logger.section("Messages")
      let steps = try await result.steps
      for (index, step) in steps.enumerated() {
        Logger.info("Step #\(index):")
        for message in step.response.messages {
          switch message {
          case .assistant(let assistant):
            switch assistant.content {
            case .text(let text):
              Logger.info("assistant: " + Helpers.truncate(text, to: 200))
            case .parts(let parts):
              Logger.info("assistant parts: \(parts.count)")
            }
          case .tool(let tool):
            Logger.info("tool message parts: \(tool.content.count)")
          }
        }
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
