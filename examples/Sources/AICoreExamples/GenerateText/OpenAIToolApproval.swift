import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolApprovalExample: Example {
  static let name = "generate-text/openai-tool-approval"
  static let description = "Demonstrates manual approval flow for typed tools." 

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  static func run() async throws {
    guard let apiKeyPrefix = try? EnvLoader.require("OPENAI_API_KEY").prefix(8) else {
      Logger.warning("Skipping network call: missing OPENAI_API_KEY")
      return
    }
    Logger.debug("Using OPENAI_API_KEY prefix: \(apiKeyPrefix)...")

    let weatherTool = tool(
      description: "Get the weather in a location",
      inputSchema: WeatherQuery.self,
      needsApproval: .always
    ) { query, _ in
      WeatherReport(
        location: query.location,
        temperatureFahrenheit: Int.random(in: 62...82)
      )
    }

    Logger.section("Instructions")
    Logger.info("Type a message to chat with the model. Enter 'exit' or an empty line to stop.")
    Logger.info("When prompted, answer with 'y' or 'n' to approve a tool call.")
    Logger.separator()

    var messages: [ModelMessage] = []
    var pendingToolResponses: [ToolContentPart] = []

    while true {
      if pendingToolResponses.isEmpty {
        guard let userInput = prompt("You: "), !userInput.isEmpty else {
          Logger.info("Conversation ended.")
          break
        }
        if userInput.lowercased() == "exit" {
          Logger.info("Conversation ended.")
          break
        }
        messages.append(.user(UserModelMessage(content: .text(userInput))))
      } else {
        messages.append(.tool(ToolModelMessage(content: pendingToolResponses)))
        pendingToolResponses.removeAll()
      }

      do {
        let result = try await generateText(
          model: openai("gpt-4.1-mini"),
          tools: ["weather": weatherTool.tool],
          system: "When a tool execution is not approved by the user, do not retry it. Just say that the tool execution was not approved.",
          messages: messages,
          stopWhen: [stepCountIs(5)]
        )

        Logger.section("Assistant")
        for part in result.content {
          switch part {
          case .text(let text, _):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Logger.info(text)
            }

          case .toolApprovalRequest(let approvalRequest):
            guard case .static = approvalRequest.toolCall else {
              Logger.warning("Received dynamic tool approval request for \(approvalRequest.toolCall.toolName); skipping.")
              continue
            }

            do {
              let input = try await weatherTool.decodeInput(from: approvalRequest.toolCall)
              let approved = promptApproval(for: input.location)
              let response = ToolApprovalResponse(approvalId: approvalRequest.approvalId, approved: approved)
              pendingToolResponses.append(.toolApprovalResponse(response))
              Logger.info(approved ? "Approved weather lookup for \(input.location)." : "Denied weather lookup for \(input.location).")
            } catch {
              Logger.error("Failed to decode tool input: \(error.localizedDescription)")
            }

          default:
            continue
          }
        }

        Logger.separator()
        messages.append(contentsOf: result.response.messages.map { message in
          switch message {
          case .assistant(let assistant):
            return .assistant(assistant)
          case .tool(let tool):
            return .tool(tool)
          }
        })
      } catch {
        Logger.warning("Skipping network call due to error: \(error.localizedDescription)")
        break
      }
    }
  }

  private static func prompt(_ label: String) -> String? {
    FileHandle.standardOutput.write(Data(label.utf8))
    return readLine(strippingNewline: true)
  }

  private static func promptApproval(for location: String) -> Bool {
    while true {
      guard let answer = prompt("Approve weather lookup for \(location)? (y/n): ")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return false
      }

      if ["y", "yes"].contains(answer) {
        return true
      }
      if ["n", "no"].contains(answer) {
        return false
      }

      Logger.info("Please answer with 'y' or 'n'.")
    }
  }
}
