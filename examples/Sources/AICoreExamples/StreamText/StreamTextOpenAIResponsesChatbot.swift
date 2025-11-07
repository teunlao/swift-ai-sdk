import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesChatbotExample: Example {
  static let name = "stream-text/openai-responses-chatbot"
  static let description = "Simple chatbot streamed via the OpenAI Responses API (system + messages)."

  static func run() async throws {
    do {
      let result = try streamText(
        model: openai.responses("gpt-4o-mini"),
        system: "You are a concise assistant.",
        messages: [
          .user(UserModelMessage(content: .text("Give me 3 short productivity tips for Swift developers.")))
        ]
      )

      Logger.section("Chatbot output")
      for try await delta in result.textStream {
        print(delta, terminator: "")
      }
      print("")

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
