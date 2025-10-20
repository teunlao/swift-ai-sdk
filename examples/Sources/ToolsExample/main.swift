/**
 Tools Example

 Demonstrates using tools (function calling) with generateText.
 Corresponds to: apps/docs/src/content/docs/getting-started/ios-macos-quickstart.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProviderUtils
import ExamplesCore

@main
struct ToolsExample: CLIExample {
  static let name = "Tools / Function Calling"
  static let description = "Use tools to extend model capabilities"

  static func run() async throws {
    Logger.info("Defining a simple echo tool...")

    // Define a tool that echoes back its input
    let echo = tool(
      description: "Echo back the input data",
      inputSchema: FlexibleSchema(jsonSchema(
        .object([
          "type": .string("object"),
          "additionalProperties": .bool(true)
        ])
      )),
      execute: { input, _ in
        Logger.info("Tool called with input: \(input)")
        return .value(input)
      }
    )

    Logger.info("Calling model with tool available...")

    // Call model with tool
    let result = try await generateText(
      model: .v3(openai("gpt-4o")),
      tools: ["echo": echo],
      prompt: "Call the echo tool with {\"message\": \"Hello from Swift AI SDK!\"}"
    )

    // Display result
    Logger.section("Result")
    print(result.text)

    // Show tool calls
    if !result.toolCalls.isEmpty {
      Logger.separator()
      Logger.info("Tool calls made: \(result.toolCalls.count)")
      for toolCall in result.toolCalls {
        Logger.info("  - \(toolCall.toolName): \(toolCall.input)")
      }
    }

    // Show tool results
    if !result.toolResults.isEmpty {
      Logger.separator()
      Logger.info("Tool results: \(result.toolResults.count)")
      for toolResult in result.toolResults {
        Logger.info("  - \(toolResult.toolName): \(toolResult.output)")
      }
    }
  }
}
