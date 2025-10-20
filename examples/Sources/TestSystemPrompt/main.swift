import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct TestSystemPrompt: CLIExample {
  static let name = "Test System Prompt"
  static let description = "Test system parameter"

  static func run() async throws {
    print("Test 1: Without system prompt...")
    let result1 = try await generateText(
      model: openai("gpt-5-mini"),
      prompt: "Say hello in one sentence."
    )
    print("Result 1: \(result1.text)")

    print("\nTest 2: With system prompt...")
    let result2 = try await generateText(
      model: openai("gpt-5-mini"),
      system: "You are a helpful assistant.",
      prompt: "Say hello in one sentence."
    )
    print("Result 2: \(result2.text)")
  }
}
