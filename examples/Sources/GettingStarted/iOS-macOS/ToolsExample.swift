/**
 Tools Example

 Demonstrates using tools (function calling) with generateText.
 Corresponds to: apps/docs/src/content/docs/getting-started/ios-macos-quickstart.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

struct EchoPayload: Codable, Sendable {
  let message: String
}

@main
struct ToolsExample: CLIExample {
  static let name = "Tools / Function Calling"
  static let description = "Use tools to extend model capabilities"

  static func run() async throws {
    try EnvLoader.load()

    Logger.section("Defining echo tool")

    let echo = tool(
      description: "Echo back the input data",
      inputSchema: EchoPayload.self
    ) { payload, _ in
      Logger.info("Tool called with message: \(payload.message)")
      return EchoPayload(message: payload.message.uppercased())
    }

    Logger.section("Calling model with tool")

    let result = try await generateText(
      model: openai("gpt-4o"),
      tools: ["echo": echo.eraseToTool()],
      prompt: "Call the echo tool with {\"message\": \"Hello from Swift AI SDK!\"}"
    )

    Logger.info("Text: \(result.text)")

    for call in result.toolCalls where !call.isDynamic {
      let input = try await echo.decodeInput(from: call)
      Logger.info("Tool call: \(call.toolName) message=\(input.message)")
    }

    for toolResult in result.toolResults where !toolResult.isDynamic {
      let output: EchoPayload = try echo.decodeOutput(from: toolResult)
      Logger.info("Tool result: \(toolResult.toolName) message=\(output.message)")
    }
  }
}
