import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesCodeInterpreterExample: Example {
  static let name = "stream-text/openai-responses-code-interpreter"
  static let description = "OpenAI Responses using the codeInterpreter tool (emits code execution output)."

  static func run() async throws {
    do {
      let codeTool = openai.tools.codeInterpreter()

      let providerOptions = openai.options.responses(include: [.codeInterpreterCallOutputs])

      let result = try streamText(
        model: openai.responses("gpt-4.1-mini"),
        system: "Use the code interpreter when math or CSV processing is needed.",
        messages: [
          .user(UserModelMessage(content: .text("Generate the first 10 squares and return their sum using python.")))
        ],
        tools: [
          "code_interpreter": codeTool
        ],
        providerOptions: providerOptions
      )

      Logger.section("Streamed output")
      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
