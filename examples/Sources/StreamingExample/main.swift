/**
 Streaming Text Example

 Demonstrates streaming text generation for real-time output.
 Corresponds to: apps/docs/src/content/docs/getting-started/ios-macos-quickstart.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct StreamingExample: CLIExample {
  static let name = "Streaming Text Generation"
  static let description = "Stream text generation for real-time output"

  static func run() async throws {
    Logger.info("Streaming text generation...")

    let prompt = "Write a haiku about vectors and embeddings"
    Logger.info("Prompt: \(prompt)")
    Logger.separator()

    // Stream text
    let stream = try streamText(
      model: .v3(openai("gpt-4o")),
      prompt: prompt,
      onFinish: { event in
        // Called when streaming completes
        Logger.separator()
        Logger.info("Streaming complete")
        Logger.info("Total tokens: \(event.totalUsage.totalTokens)")
        Logger.info("Finish reason: \(event.finishReason)")
      }
    )

    // Iterate over text deltas
    Logger.section("Streamed Output")
    for try await chunk in stream.textStream {
      print(chunk, terminator: "")
      fflush(stdout)
    }
    print() // New line after streaming
  }
}
