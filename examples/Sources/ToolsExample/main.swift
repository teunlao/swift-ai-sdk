/**
 Tools Example

 Demonstrates using tools (function calling) with generateText.
 Corresponds to: apps/docs/src/content/docs/getting-started/ios-macos-quickstart.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProviderUtils
import AISDKZodAdapter
import ExamplesCore

@main
struct ToolsExample: CLIExample {
  static let name = "Tools / Function Calling"
  static let description = "Use tools to extend model capabilities"

  static func run() async throws {
    // Example 1: Tool with manual JSON schema
    Logger.section("Example 1: Tool with Manual JSON Schema")
    Logger.info("Defining echo tool with jsonSchema()...")

    let echo = tool(
      description: "Echo back the input data",
      inputSchema: FlexibleSchema(jsonSchema(
        .object([
          "type": .string("object"),
          "properties": .object([
            "message": .object([
              "type": .string("string"),
              "description": .string("The message to echo back")
            ])
          ]),
          "required": .array([.string("message")]),
          "additionalProperties": .bool(false)
        ])
      )),
      execute: { input, _ in
        Logger.info("Echo tool called with: \(input)")
        return .value(input)
      }
    )

    let result1 = try await generateText(
      model: openai("gpt-4o"),
      tools: ["echo": echo],
      prompt: "Call the echo tool with {\"message\": \"Hello from Swift AI SDK!\"}"
    )

    Logger.info("Result: \(result1.text)")
    if !result1.toolCalls.isEmpty {
      Logger.info("Tool calls: \(result1.toolCalls.count)")
    }

    // Example 2: Tool with Zod-like schema (cleaner!)
    Logger.section("Example 2: Tool with Zod-like Schema")
    Logger.info("Defining calculator tool with z.object()...")

    let calculator = tool(
      description: "Perform basic arithmetic operations",
      inputSchema: flexibleSchemaFromZod3(z.object([
        "operation": z.string(),
        "a": z.number(),
        "b": z.number()
      ])),
      execute: { input, _ in
        Logger.info("Calculator tool called with: \(input)")

        guard case .object(let obj) = input,
              case .string(let op) = obj["operation"] ?? .null,
              case .number(let a) = obj["a"] ?? .null,
              case .number(let b) = obj["b"] ?? .null else {
          return .value(.string("Invalid input"))
        }

        let result: Double
        switch op {
        case "add": result = a + b
        case "subtract": result = a - b
        case "multiply": result = a * b
        case "divide": result = b != 0 ? a / b : 0
        default: result = 0
        }

        return .value(.number(result))
      }
    )

    let result2 = try await generateText(
      model: openai("gpt-4o"),
      tools: ["calculator": calculator],
      prompt: "What is 234 multiplied by 89? Use the calculator tool."
    )

    Logger.info("Result: \(result2.text)")

    // Show tool calls for calculator
    if !result2.toolCalls.isEmpty {
      Logger.separator()
      Logger.info("Tool calls made: \(result2.toolCalls.count)")
      for toolCall in result2.toolCalls {
        Logger.info("  - \(toolCall.toolName): \(toolCall.input)")
      }
    }

    // Show tool results for calculator
    if !result2.toolResults.isEmpty {
      Logger.separator()
      Logger.info("Tool results: \(result2.toolResults.count)")
      for toolResult in result2.toolResults {
        Logger.info("  - \(toolResult.toolName): \(toolResult.output)")
      }
    }
  }
}
