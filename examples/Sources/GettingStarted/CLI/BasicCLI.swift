/**
 Basic CLI Example

 A command-line tool that streams AI output to stdout.
 Corresponds to: apps/docs/src/content/docs/getting-started/cli-quickstart.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct BasicCLI: CLIExample {
  static let name = "Command-Line Interface"
  static let description = "Stream AI responses to terminal"

  static func run() async throws {
    // Get prompt from command line arguments or use default
    let args = CommandLine.arguments.dropFirst()
    let prompt = args.joined(separator: " ").isEmpty
      ? "Write a limerick about SwiftPM"
      : args.joined(separator: " ")

    Logger.info("Prompt: \(prompt)")
    Logger.separator()

    // Stream response to stdout
    let stream = try streamText(
      model: openai("gpt-4o"),
      prompt: prompt
    )

    for try await delta in stream.textStream {
      print(delta, terminator: "")
      fflush(stdout)
    }
    print() // New line at end
  }
}
