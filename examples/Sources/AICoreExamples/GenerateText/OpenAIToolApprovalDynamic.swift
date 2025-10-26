import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolApprovalDynamicExample: Example {
  static let name = "generate-text/openai-tool-approval-dynamic"
  static let description =
    "Handles approvals for dynamic tools where schemas are only known at runtime."

  private struct WeatherQuery: Codable, Sendable {
    let location: String
  }

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

    let tools: [String: Tool] = [
      "weather": dynamicTool(
        description: "Get the weather in a location",
        inputSchema: WeatherQuery.self,
        needsApproval: .always
      ) { query, _ in
        WeatherReport(
          location: query.location,
          temperatureFahrenheit: Int.random(in: 62...82)
        )
      }
    ]

    Logger.section("Instructions")
    Logger.info("Type a message to chat with the model. Enter 'exit' or an empty line to stop.")
    Logger.info("When prompted, answer with 'y' or 'n' to approve a tool call.")
    Logger.separator()

    var messages: [ModelMessage] = []
    var pendingApprovals: [ToolContentPart] = []

    while true {
      if pendingApprovals.isEmpty {
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
        messages.append(.tool(ToolModelMessage(content: pendingApprovals)))
        pendingApprovals.removeAll()
      }

      do {
        let result = try await generateText(
          model: openai("gpt-4.1-mini"),
          tools: tools,
          system:
            "When a tool execution is not approved by the user, do not retry it. Just say that the tool execution was not approved.",
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
            handleApprovalRequest(approvalRequest, accumulating: &pendingApprovals)

          default:
            continue
          }
        }

        Logger.separator()
        messages.append(contentsOf: result.response.messages.map(Self.convertResponseMessage))
      } catch {
        Logger.warning("Skipping network call due to error: \(error.localizedDescription)")
        break
      }
    }
  }

  // MARK: - Helpers

  private static func handleApprovalRequest(
    _ request: ToolApprovalRequestOutput,
    accumulating container: inout [ToolContentPart]
  ) {
    let toolName = request.toolCall.toolName
    let inputDescription = prettyPrintedJSON(request.toolCall.input)

    let approved = promptApproval(
      message: "Approve execution of \(toolName) with input \(inputDescription)? (y/n): "
    )

    let response = ToolApprovalResponse(approvalId: request.approvalId, approved: approved)
    container.append(.toolApprovalResponse(response))

    Logger.info(
      approved
        ? "Approved \(toolName) call."
        : "Denied \(toolName) call.")
  }

  private static func prompt(_ label: String) -> String? {
    FileHandle.standardOutput.write(Data(label.utf8))
    return readLine(strippingNewline: true)
  }

  private static func promptApproval(message: String) -> Bool {
    while true {
      guard
        let answer = prompt(message)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      else {
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

  private static func convertResponseMessage(_ message: ResponseMessage) -> ModelMessage {
    switch message {
    case .assistant(let assistant):
      return .assistant(assistant)
    case .tool(let tool):
      return .tool(tool)
    }
  }

  private static func prettyPrintedJSON(_ value: JSONValue) -> String {
    let foundation = jsonValueToFoundation(value)
    if JSONSerialization.isValidJSONObject(foundation),
      let data = try? JSONSerialization.data(
        withJSONObject: foundation, options: [.sortedKeys, .prettyPrinted]),
      let string = String(data: data, encoding: .utf8)
    {
      return string.replacingOccurrences(of: "\n", with: " ")
    }

    return "\(value)"
  }
}
