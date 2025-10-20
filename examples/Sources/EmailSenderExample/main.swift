/**
 Email Sender Tool Example (Zod Adapter)

 Demonstrates using Zod-like DSL with validation (email, url, string length).
 Corresponds to: apps/docs/src/content/docs/zod-adapter/overview.mdx
 Example 3: Email Sender Tool
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProviderUtils
import AISDKZodAdapter
import ExamplesCore

@main
struct EmailSenderExample: CLIExample {
  static let name = "Zod Adapter: Email Sender Tool"
  static let description = "Use Zod DSL with email/url validation and length constraints"

  static func run() async throws {
    Logger.section("Email Sender Tool with Zod DSL")

    let sendEmail = tool(
      description: "Send an email",
      inputSchema: flexibleSchemaFromZod3(z.object([
        "to": z.string(email: true),
        "subject": z.string(minLength: 1, maxLength: 200),
        "body": z.string(),
        "attachments": z.optional(z.array(of: z.string(url: true)))
      ])),
      execute: { input, _ in
        Logger.info("Email sender tool called with: \(input)")

        guard case .object(let obj) = input,
              case .string(let to) = obj["to"] ?? .null,
              case .string(let subject) = obj["subject"] ?? .null,
              case .string(let body) = obj["body"] ?? .null else {
          return .value(.string("Missing required fields"))
        }

        // Simulate sending email
        Logger.info("Sending email to: \(to)")
        Logger.info("Subject: \(subject)")
        Logger.info("Body: \(body)")

        // Check for attachments
        if case .array(let attachments) = obj["attachments"] ?? .null {
          Logger.info("Attachments: \(attachments.count) file(s)")
        }

        // Return success response
        return .value(.object([
          "status": .string("sent"),
          "messageId": .string("msg_123abc")
        ]))
      }
    )

    // Use the tool
    let result = try await generateText(
      model: openai("gpt-4o"),
      tools: ["sendEmail": sendEmail],
      prompt: "Send an email to user@example.com with subject 'Meeting Reminder' and body 'Don't forget about our meeting tomorrow at 10 AM.'"
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
