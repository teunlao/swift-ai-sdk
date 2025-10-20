/**
 Calculator Tool Example (Zod Adapter)

 Demonstrates using Zod-like DSL for tool schemas.
 Corresponds to: apps/docs/src/content/docs/zod-adapter/overview.mdx
 Example 1: Simple Calculator Tool
 */

import AISDKProviderUtils
import AISDKZodAdapter
import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

@main
struct CalculatorExample: CLIExample {
  static let name = "Zod Adapter: Calculator Tool"
  static let description = "Use Zod DSL to define calculator tool schema"

  static func run() async throws {
    Logger.section("Calculator Tool with Zod DSL")

    let calculator = tool(
      description: "Perform basic arithmetic operations",
      inputSchema: flexibleSchemaFromZod3(
        z.object([
          "operation": z.string(),  // "add", "subtract", "multiply", "divide"
          "a": z.number(),
          "b": z.number(),
        ])),
      execute: { input, _ in
        Logger.info("Calculator tool called with: \(input)")

        guard case .object(let obj) = input,
          case .string(let op) = obj["operation"] ?? .null,
          case .number(let a) = obj["a"] ?? .null,
          case .number(let b) = obj["b"] ?? .null
        else {
          return .value(.string("Invalid input"))
        }

        let result: Double
        switch op {
        case "add": result = a + b
        case "subtract": result = a - b
        case "multiply": result = a * b
        case "divide": result = b != 0 ? a / b : 0
        default: return .value(.string("Unknown operation"))
        }

        return .value(.number(result))
      }
    )

    // Use the tool
    let result = try await generateText(
      model: openai("gpt-4o"),
      tools: ["calculator": calculator],
      prompt: "What is 234 multiplied by 89? Use the calculator tool."
    )

    Logger.separator()
    Logger.info("Result: \(result.text)")

    if !result.toolCalls.isEmpty {
      Logger.separator()
      Logger.info("Tool calls made: \(result.toolCalls.count)")
      for toolCall in result.toolCalls {
        Logger.info("  - \(toolCall.toolName): \(toolCall.input)")
      }
    }
  }
}
