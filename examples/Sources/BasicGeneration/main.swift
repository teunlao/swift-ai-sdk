/**
 Basic Text Generation Example

 Demonstrates the simplest way to generate text using the Swift AI SDK.
 Corresponds to: apps/docs/src/content/docs/getting-started/ios-macos-quickstart.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProvider
import ExamplesCore

@main
struct BasicGeneration: CLIExample {
  static let name = "Basic Text Generation"
  static let description = "Generate text with a simple prompt using OpenAI"

  static func run() async throws {
    Logger.info("Generating text from a simple prompt...")

    // Generate text
    let result = try await generateText(
      model: .v3(openai("gpt-4o")),
      prompt: "Write a 1-sentence product tagline for a time-tracking app.",
      experimentalOutput: nil as Output.Specification<Never, JSONValue>?
    )

    // Display result
    Logger.section("Generated Text")
    print(result.text)

    // Show metadata
    Logger.separator()
    Logger.info("Tokens used: \(result.usage.totalTokens)")
    Logger.info("Finish reason: \(result.finishReason)")
  }
}
