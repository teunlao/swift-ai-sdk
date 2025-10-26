import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAILogprobsExample: Example {
  static let name = "generate-text/openai-logprobs"
  static let description = "Requests token log probabilities from OpenAI and prints provider metadata."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let providerOptions: ProviderOptions = [
        "openai": [
          "logprobs": .number(2)
        ]
      ]

      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        prompt: "Invent a new holiday and describe its traditions.",
        providerOptions: providerOptions
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Provider Metadata")
      if let metadata = result.providerMetadata,
         let openAIData = metadata["openai"],
         let logprobs = openAIData["logprobs"],
         let json = encodeMetadata(["openai": ["logprobs": logprobs]]) {
        Logger.info(json)
      } else {
        Logger.info("<no logprobs metadata>")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func encodeMetadata(_ value: [String: [String: JSONValue]]) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(value)
      return String(data: data, encoding: .utf8)
    } catch {
      return nil
    }
  }
}
