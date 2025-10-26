import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAINullableToolExample: Example {
  static let name = "generate-text/openai-nullable"
  static let description = "Demonstrates optional tool parameters mapped to nullable JSON schema." 

  private struct ExecuteCommandInput: Codable, Sendable {
    let command: String
    let workdir: String?
    let timeout: String?
  }

  private struct ExecuteCommandOutput: Codable, Sendable {
    let message: String
  }

  static func run() async throws {
    let executeCommand = tool(
      description: "Execute a command with optional working directory and timeout",
      inputSchema: ExecuteCommandInput.self
    ) { input, _ in
      let workdir = input.workdir ?? "current dir"
      let timeout = input.timeout ?? "default"
      return ExecuteCommandOutput(
        message: "Executed: \(input.command) in \(workdir) with timeout \(timeout)"
      )
    }

    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        tools: ["executeCommand": executeCommand.tool],
        prompt: "List the files in the /tmp directory with a 30 second timeout",
        settings: CallSettings(temperature: 0)
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Tool Results")
      for toolResult in result.toolResults {
        switch toolResult {
        case .static(let staticResult) where staticResult.toolName == "executeCommand":
          do {
            let decoded = try executeCommand.decodeOutput(from: toolResult)
            Logger.info(decoded.message)
          } catch {
            Logger.error("Failed to decode tool output: \(error.localizedDescription)")
          }
        default:
          Logger.info("Unhandled tool result: \(toolResult)")
        }
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
