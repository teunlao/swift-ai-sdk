import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIToolApprovalExample: Example {
  static let name = "stream-text/openai-tool-approval"
  static let description = "Demonstrates automatic approval with toolApproval."

  private struct EchoInput: Codable, Sendable { let text: String }
  private struct EchoOutput: Codable, Sendable { let echoed: String }

  static func run() async throws {
    do {
      let echo: TypedTool<EchoInput, EchoOutput> = tool(
        description: "Echo back the provided text.",
        inputSchema: .auto(EchoInput.self),
        outputSchema: .auto(EchoOutput.self)
      ) { input, _ in
        EchoOutput(echoed: input.text)
      }

      let result = try streamText(
        model: openai("gpt-5-mini"),
        tools: ["echo": echo.tool],
        prompt: "Use the echo tool to repeat: 'Swift AI SDK'.",
        toolApproval: .generic { request in
          Logger.info("approve tool: \(request.toolCall.toolName)")
          return .approved()
        }
      )

      for try await chunk in result.textStream { print(chunk, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
