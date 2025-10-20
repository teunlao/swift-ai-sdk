/**
 Database Query Tool Example (Zod Adapter)

 Demonstrates using Zod-like DSL with optional fields and nested objects.
 Corresponds to: apps/docs/src/content/docs/zod-adapter/overview.mdx
 Example 2: Database Query Tool
 */

import AISDKProviderUtils
import AISDKZodAdapter
import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

@main
struct DatabaseQueryExample: CLIExample {
  static let name = "Zod Adapter: Database Query Tool"
  static let description = "Use Zod DSL with optional fields and validation"

  static func run() async throws {
    Logger.section("Database Query Tool with Zod DSL")

    let dbQuery = tool(
      description: "Query the database",
      inputSchema: flexibleSchemaFromZod3(
        z.object([
          "table": z.string(),
          "filters": z.optional(
            z.object([
              "field": z.string(),
              "value": z.string(),
            ])),
          "limit": z.optional(z.number(min: 1, max: 100, integer: true)),
        ])),
      execute: { input, _ in
        Logger.info("Database query tool called with: \(input)")

        guard case .object(let obj) = input,
          case .string(let table) = obj["table"] ?? .null
        else {
          return .value(.string("Table name required"))
        }

        // Simulate database query
        Logger.info("Querying table: \(table)")

        // Check for filters
        if case .object(let filters) = obj["filters"] ?? .null {
          Logger.info("Applying filters: \(filters)")
        }

        // Check for limit
        if case .number(let limit) = obj["limit"] ?? .null {
          Logger.info("Limiting results to: \(Int(limit))")
        }

        // Return mock data
        return .value(
          .object([
            "count": .number(42),
            "rows": .array([
              .object(["id": .number(1), "name": .string("Alice")]),
              .object(["id": .number(2), "name": .string("Bob")]),
            ]),
          ]))
      }
    )

    // Use the tool
    let result = try await generateText(
      model: openai("gpt-4o"),
      tools: ["dbQuery": dbQuery],
      prompt: "Query the users table and filter by name='Alice', limit to 10 results."
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

    if !result.toolResults.isEmpty {
      Logger.separator()
      Logger.info("Tool results: \(result.toolResults.count)")
      for toolResult in result.toolResults {
        Logger.info("  - \(toolResult.toolName): \(toolResult.output)")
      }
    }
  }
}
