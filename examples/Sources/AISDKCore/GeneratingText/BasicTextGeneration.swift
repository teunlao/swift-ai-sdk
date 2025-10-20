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
    let article = "The Swift AI SDK provides a unified interface for working with multiple LLM providers..."

    let withSystem = try await generateText(
      model: openai("gpt-4o"),
      system: "You are a professional writer. You write simple, clear, and concise content.",
      prompt: "Summarize the following article in 3-5 sentences: \(article)"
    )
    print(withSystem.text)

    // Example 3: With settings
    Logger.section("Example 3: With Temperature Settings")
    let creative = try await generateText(
      model: openai("gpt-4o"),
      settings: CallSettings(
        temperature: 0.9,
        maxOutputTokens: 100
      ),
      prompt: "Invent a new holiday and describe its traditions."
    )
    print(creative.text)

    // Show usage stats
    Logger.separator()
    Logger.info("Total tokens used: \(simple.usage.totalTokens + withSystem.usage.totalTokens + creative.usage.totalTokens)")
  }
}
