/**
 Basic Text Generation (AI SDK Core)

 Demonstrates core text generation capabilities with various options.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/generating-text.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct BasicTextGeneration: CLIExample {
  static let name = "AI SDK Core: Text Generation"
  static let description = "Explore generateText with system prompts and settings"

  static func run() async throws {
    // Example 1: Simple generation
    Logger.section("Example 1: Simple Generation")
    let simple = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Write a vegetarian lasagna recipe for 4 people."
    )
    print(Helpers.truncate(simple.text, to: 200))

    // Example 2: With system prompt
    Logger.section("Example 2: With System Prompt")

    let withSystem = try await generateText(
      model: openai("gpt-4o"),
      system: "You are a professional writer. You write simple, clear, and concise content.",
      prompt: "Write a one-sentence summary about the benefits of using Swift for iOS development."
    )
    print(withSystem.text)

    // Example 3: With settings
    Logger.section("Example 3: With Temperature Settings")
    let creative = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Invent a new holiday and describe its traditions.",
      settings: CallSettings(
        maxOutputTokens: 100,
        temperature: 0.9
      )
    )
    print(creative.text)

    // Show usage stats
    Logger.separator()
    let totalTokens = (simple.usage.totalTokens ?? 0) + (withSystem.usage.totalTokens ?? 0) + (creative.usage.totalTokens ?? 0)
    Logger.info("Total tokens used: \(totalTokens)")
  }
}
