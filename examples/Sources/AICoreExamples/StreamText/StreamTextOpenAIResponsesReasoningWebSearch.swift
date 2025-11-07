import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesReasoningWebSearchExample: Example {
  static let name = "stream-text/openai-responses-reasoning-websearch"
  static let description = "Use OpenAI Responses reasoning with provider web_search tool and reuse the transcript."

  static func run() async throws {
    do {
      let providerOptions = openai.options.responses(
        reasoningEffort: "medium",
        reasoningSummary: "detailed"
      )

      let result = try streamText(
        model: openai.responses("gpt-5-mini"),
        prompt: "What happened in the world today?",
        tools: ["web_search": openai.tools.webSearch()],
        providerOptions: providerOptions
      )

      for try await chunk in result.textStream {
        print(chunk, terminator: "")
      }
      print("")

      let response = try await result.response
      Logger.section("Response messages (assistant/tool order)")
      for message in response.messages {
        switch message {
        case .assistant(let assistant):
          switch assistant.content {
          case .text(let text):
            Logger.info("assistant text: " + Helpers.truncate(text, to: 200))
          case .parts(let parts):
            Logger.info("assistant parts: \(parts.count)")
          }
        case .tool(let tool):
          Logger.info("tool message parts: \(tool.content.count)")
        }
      }

      let followUp = try await generateText(
        model: openai.responses("gpt-5-mini"),
        messages: response.messages + [.user("Summarize in 2 sentences.")]
      )

      Logger.section("Follow-up summary")
      Logger.info(followUp.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
