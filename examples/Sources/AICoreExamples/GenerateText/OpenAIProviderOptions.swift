import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIProviderOptionsExample: Example {
  static let name = "generate-text/openai-provider-options"
  static let description = "Demonstrates advanced OpenAI-specific provider options (logprobs, cache, tiers, etc.)."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let providerOptions: ProviderOptions = [
        "openai": [
          "logitBias": .object([:]),
          "logprobs": .number(1),
          "user": .string("<user_id>"),
          "maxCompletionTokens": .number(100),
          "store": .bool(false),
          "structuredOutputs": .bool(false),
          "serviceTier": .string("auto"),
          "strictJsonSchema": .bool(false),
          "textVerbosity": .string("medium"),
          "promptCacheKey": .string("<prompt_cache_key>"),
          "safetyIdentifier": .string("<safety_identifier>"),
          "invalidOption": .null
        ]
      ]

      let result = try await generateText(
        model: openai.chat("gpt-4o"),
        prompt: "Invent a new holiday and describe its traditions.",
        providerOptions: providerOptions
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Usage")
      Helpers.printJSON(result.totalUsage)

      if let metadata = result.providerMetadata {
        Logger.section("Provider Metadata")
        Helpers.printJSON(metadata)
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
