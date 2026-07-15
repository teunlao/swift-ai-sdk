import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIProviderOptionsExample: Example {
  static let name = "generate-text/openai-provider-options"
  static let description = "Demonstrates GPT-5.6 reasoning, prompt caching, and request controls."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let providerOptions: ProviderOptions = [
        "openai": [
          "user": .string("<user_id>"),
          "store": .bool(false),
          "serviceTier": .string("auto"),
          "strictJsonSchema": .bool(false),
          "textVerbosity": .string("medium"),
          "promptCacheKey": .string("<prompt_cache_key>"),
          "promptCacheOptions": .object([
            "mode": .string("implicit"),
            "ttl": .string("30m")
          ]),
          "reasoningEffort": .string("max"),
          "reasoningMode": .string("pro"),
          "reasoningContext": .string("all_turns"),
          "reasoningSummary": .string("auto"),
          "safetyIdentifier": .string("<safety_identifier>"),
        ]
      ]

      let result = try await generateText(
        model: openai("gpt-5.6"),
        prompt: "Invent a new holiday and describe its traditions.",
        providerOptions: providerOptions,
        settings: CallSettings(maxOutputTokens: 100)
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
