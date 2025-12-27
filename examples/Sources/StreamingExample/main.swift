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

    // Stream text - request objects let you build a reusable base config.
    var request = StreamTextRequest(model: openai("gpt-4o"))
    request.prompt = prompt
    request.onFinish = { finalStep, steps, totalUsage, finishReason in
      // Called when streaming completes
      Logger.separator()
      Logger.info("Streaming complete")
      Logger.info("Total tokens: \(totalUsage.totalTokens ?? 0)")
      Logger.info("Finish reason: \(finishReason)")
    }

    let stream = try streamText(request)

    // Iterate over text deltas
    Logger.section("Streamed Output")
    for try await chunk in stream.textStream {
      print(chunk, terminator: "")
      fflush(stdout)
    }
    print() // New line after streaming
  }
}
