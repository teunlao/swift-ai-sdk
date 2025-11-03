import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnFinishResponseMessagesExample: Example {
  static let name = "stream-text/openai-on-finish-response-messages"
  static let description = "Print response.messages from final step in onFinish."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "Say hello and explain what response messages are.",
        onFinish: { finalStep, _, _, _ in
          Logger.section("response.messages")
          Helpers.printJSON(finalStep.response.messages.map { $0.describe() })
        }
      )
      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

private extension ResponseMessage {
  func describe() -> [String: String] {
    switch self {
    case .assistant(let msg):
      switch msg.content {
      case .text(let text):
        return ["type": "assistant", "content": String(text.prefix(120))]
      case .parts(let parts):
        return ["type": "assistant", "parts": "\(parts.count)"]
      }
    case .tool(let msg):
      return ["type": "tool", "parts": "\(msg.content.count)"]
    }
  }
}
