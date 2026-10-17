/**
 Provider Management Example

 Demonstrates custom providers and provider registry.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/provider-management.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct ProviderManagementExample: CLIExample {
  static let name = "Provider & Model Management"
  static let description = "Manage multiple providers and models"

  static func run() async throws {
    // Example 1: Custom Provider with Model Aliases
    Logger.section("Example 1: Custom Provider with Model Aliases")
    Logger.info("Creating custom provider with semantic names...")

    let customOpenAI = customProvider(
      languageModels: [
        // Semantic aliases for easy version updates
        "fast": try openai.languageModel("gpt-4o-mini"),
        "smart": try openai.languageModel("gpt-4o"),
        "reasoning": wrapLanguageModel(
          model: try openai.languageModel("gpt-4o"),
          middleware: .single(defaultSettingsMiddleware(
            settings: DefaultSettings(
              maxOutputTokens: 500,
              temperature: 0.3
            )
          ))
        )
      ],
      fallbackProvider: openai  // Falls back for undefined models
    )

    Logger.info("Using alias 'fast' → gpt-4o-mini:")
    let fastResult = try await generateText(
      model: customOpenAI.languageModel(modelId: "fast"),
      prompt: "Count from 1 to 3"
    )
    Logger.info(fastResult.text)

    Logger.info("Using alias 'reasoning' with pre-configured settings:")
    let reasoningResult = try await generateText(
      model: customOpenAI.languageModel(modelId: "reasoning"),
      prompt: "What is 2+2?"
    )
    Logger.info(reasoningResult.text)

    // Example 2: Provider Registry with Default Separator
    Logger.section("Example 2: Provider Registry (default separator ':')")
    Logger.info("Creating registry with multiple providers...")

    let registry = createProviderRegistry(
      providers: [
        "openai": openai,
        "custom": customOpenAI
      ]
    )

    Logger.info("Accessing model via registry: 'openai:gpt-4o-mini'")
    let registryResult = try await generateText(
      model: registry.languageModel(id: "openai:gpt-4o-mini"),
      prompt: "Say hello in Spanish"
    )
    Logger.info(registryResult.text)

    Logger.info("Accessing custom provider model: 'custom:fast'")
    let customResult = try await generateText(
      model: registry.languageModel(id: "custom:fast"),
      prompt: "Say hello in French"
    )
    Logger.info(customResult.text)

    // Example 3: Custom Separator
    Logger.section("Example 3: Registry with Custom Separator ' > '")
    Logger.info("Creating registry with readable separator...")

    let readableRegistry = createProviderRegistry(
      providers: [
        "openai": openai,
        "custom": customOpenAI
      ],
      options: ProviderRegistryOptions(separator: " > ")
    )

    Logger.info("Accessing model: 'openai > gpt-4o'")
    let separatorResult = try await generateText(
      model: readableRegistry.languageModel(id: "openai > gpt-4o"),
      prompt: "What is Swift?"
    )
    Logger.info(separatorResult.text.prefix(100) + "...")

    // Example 4: Registry with Middleware
    Logger.section("Example 4: Registry with Global Middleware")
    Logger.info("Applying reasoning extraction to all models...")

    let middlewareRegistry = createProviderRegistry(
      providers: [
        "openai": openai
      ],
      options: ProviderRegistryOptions(
        languageModelMiddleware: .single(
          extractReasoningMiddleware(
            options: ExtractReasoningOptions(tagName: "think")
          )
        )
      )
    )

    Logger.info("All models from this registry extract <think> tags:")
    let thinkResult = try await generateText(
      model: middlewareRegistry.languageModel(id: "openai:gpt-4o"),
      prompt: "Calculate 15 * 7. Wrap your reasoning in <think> tags."
    )

    let reasoning = thinkResult.content.compactMap { content -> String? in
      if case .reasoning(let reasoningPart) = content {
        return reasoningPart.text
      }
      return nil
    }.joined()

    if !reasoning.isEmpty {
      Logger.info("Extracted reasoning: \(reasoning.prefix(80))...")
    }
    Logger.info("Final answer: \(thinkResult.text)")

    // Example 5: Limited Provider (No Fallback)
    Logger.section("Example 5: Limited Provider Without Fallback")
    Logger.info("Creating provider with only specific models...")

    let limitedProvider = customProvider(
      languageModels: [
        "mini": try openai.languageModel("gpt-4o-mini"),
        "standard": try openai.languageModel("gpt-4o")
      ]
      // No fallbackProvider = only 'mini' and 'standard' available
    )

    Logger.info("Available models: 'mini', 'standard'")
    let limitedResult = try await generateText(
      model: limitedProvider.languageModel(modelId: "mini"),
      prompt: "Say 'Hello from limited provider!'"
    )
    Logger.info(limitedResult.text)

    Logger.info("⚠️  Trying to access undefined model would crash:")
    Logger.info("   limitedProvider.languageModel(modelId: \"unknown\") → fatalError")

    // Summary
    Logger.separator()
    Logger.info("Provider management examples complete!")
    Logger.info("Key concepts:")
    Logger.info("  • customProvider() - Create providers with aliases and settings")
    Logger.info("  • createProviderRegistry() - Manage multiple providers")
    Logger.info("  • Custom separators - Use : or > or / for readability")
    Logger.info("  • Middleware - Apply to all models in registry")
    Logger.info("  • Fallback providers - Gracefully handle unknown models")
  }
}
