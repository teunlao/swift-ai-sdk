/**
 Middleware Example

 Demonstrates language model middleware functionality.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/middleware.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProvider
import ExamplesCore

@main
struct MiddlewareExample: CLIExample {
  static let name = "Language Model Middleware"
  static let description = "Enhance model behavior with middleware"

  static func run() async throws {
    Logger.section("Example 1: Extract Reasoning Middleware")
    Logger.info("Extracting <think> tags from model responses...")

    // Wrap model with extractReasoningMiddleware
    let reasoningModel = wrapLanguageModel(
      model: openai("gpt-4o"),
      middleware: .single(extractReasoningMiddleware(
        options: ExtractReasoningOptions(tagName: "think")
      ))
    )

    let reasoningResult = try await generateText(
      model: reasoningModel,
      prompt: "Solve this step by step: What is 15 * 23? Wrap your thinking in <think> tags."
    )

    Logger.info("Text (without reasoning): \(reasoningResult.text)")

    // Extract reasoning content if present
    let reasoning = reasoningResult.content.compactMap { content -> String? in
      if case .reasoning(let reasoningPart) = content {
        return reasoningPart.text
      }
      return nil
    }.joined(separator: "\n")

    if !reasoning.isEmpty {
      Logger.info("Reasoning extracted: \(reasoning)")
    }

    // Example 2: Simulate Streaming Middleware
    Logger.section("Example 2: Simulate Streaming Middleware")
    Logger.info("Converting non-streaming responses to streams...")

    let streamingModel = wrapLanguageModel(
      model: openai("gpt-4o"),
      middleware: .single(simulateStreamingMiddleware())
    )

    let streamResult = try await streamText(
      model: streamingModel,
      prompt: "Count from 1 to 5"
    )

    Logger.info("Streaming chunks:")
    for try await chunk in streamResult.textStream {
      print(chunk, terminator: "")
      fflush(stdout)
    }
    print()

    // Example 3: Default Settings Middleware
    Logger.section("Example 3: Default Settings Middleware")
    Logger.info("Applying default temperature and max tokens...")

    let defaultsModel = wrapLanguageModel(
      model: openai("gpt-4o"),
      middleware: .single(defaultSettingsMiddleware(
        settings: DefaultSettings(
          maxOutputTokens: 50,
          temperature: 0.3
        )
      ))
    )

    let shortResult = try await generateText(
      model: defaultsModel,
      prompt: "Write a haiku about Swift programming"
    )

    Logger.info("Result (max 50 tokens, temp 0.3):")
    Logger.info(shortResult.text)

    // Example 4: Multiple Middlewares
    Logger.section("Example 4: Multiple Middlewares (Chained)")
    Logger.info("Combining default settings + simulated streaming...")

    let combinedModel = wrapLanguageModel(
      model: openai("gpt-4o"),
      middleware: .multiple([
        defaultSettingsMiddleware(
          settings: DefaultSettings(
            maxOutputTokens: 100,
            temperature: 0.7
          )
        ),
        simulateStreamingMiddleware()
      ])
    )

    let combinedResult = try await streamText(
      model: combinedModel,
      prompt: "Describe the Swift programming language in 2 sentences"
    )

    Logger.info("Combined result:")
    for try await chunk in combinedResult.textStream {
      print(chunk, terminator: "")
      fflush(stdout)
    }
    print()

    // Example 5: Custom Logging Middleware
    Logger.section("Example 5: Custom Logging Middleware")
    Logger.info("Creating custom middleware that logs parameters...")

    let loggingMiddleware = LanguageModelV3Middleware(
      wrapGenerate: { doGenerate, _, params, model in
        Logger.info("🔍 Logging Middleware: doGenerate called")
        Logger.info("  Model: \(model.modelId)")
        Logger.info("  Messages: \(params.prompt.count)")

        let result = try await doGenerate()

        let text = result.content.compactMap { content -> String? in
          if case .text(let textPart) = content {
            return textPart.text
          }
          return nil
        }.joined()

        Logger.info("  Generated: \(text.prefix(50))...")
        return result
      }
    )

    let loggedModel = wrapLanguageModel(
      model: openai("gpt-4o"),
      middleware: .single(loggingMiddleware)
    )

    let loggedResult = try await generateText(
      model: loggedModel,
      prompt: "What is middleware?"
    )

    Logger.info("Final result: \(loggedResult.text)")

    // Summary
    Logger.separator()
    Logger.info("Middleware examples complete!")
    Logger.info("Built-in middleware:")
    Logger.info("  • extractReasoningMiddleware - Extract reasoning from XML tags")
    Logger.info("  • simulateStreamingMiddleware - Simulate streaming from non-streaming models")
    Logger.info("  • defaultSettingsMiddleware - Apply default settings")
    Logger.info("Custom middleware can be implemented for:")
    Logger.info("  • Logging, caching, RAG, guardrails, and more")
  }
}
