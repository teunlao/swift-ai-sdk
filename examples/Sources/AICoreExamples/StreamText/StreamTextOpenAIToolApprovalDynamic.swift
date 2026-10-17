import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIToolApprovalDynamicExample: Example {
  static let name = "stream-text/openai-tool-approval-dynamic-tool"
  static let description = "Conditional tool approval (deny dangerous inputs)."

  private struct CommandInput: Codable, Sendable { let command: String }
  private struct CommandResult: Codable, Sendable { let ok: Bool; let output: String }

  static func run() async throws {
    do {
      let runCommand: TypedTool<CommandInput, CommandResult> = tool(
        description: "Run a safe command (demo).",
        inputSchema: .auto(CommandInput.self),
        outputSchema: .auto(CommandResult.self)
      ) { input, _ in
        CommandResult(ok: true, output: "executed: \(input.command)")
      }

      let result = try streamText(
        model: openai("gpt-5-mini"),
        tools: ["run_command": runCommand.tool],
        prompt: "Run the run_command tool with command 'date -u'.",
        toolApproval: .generic { request in
          let call = request.toolCall
          if call.toolName == "run_command" {
            // Deny if command looks dangerous; approve otherwise
            if case .object(let obj) = call.input, case .string(let cmd)? = obj["command"], (cmd.contains("rm ") || cmd.contains("DROP TABLE")) {
              Logger.warning("denied risky command: \(cmd)")
              return .denied()
            }
            Logger.info("approved command")
            return .approved()
          }
          return .approved()
        }
      )

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
