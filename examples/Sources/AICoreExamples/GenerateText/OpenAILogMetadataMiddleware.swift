import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAILogMetadataMiddlewareExample: Example {
  static let name = "generate-text/openai-log-metadata-middleware"
  static let description = "Logs provider options via LanguageModel middleware before delegating to OpenAI."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let logMiddleware = LanguageModelV3Middleware(transformParams: { _, params, _ in
        if let providerOptions = params.providerOptions {
          if let json = Self.encodeProviderOptions(providerOptions) {
            Logger.info("providerOptions: \(json)")
          } else {
            Logger.info("providerOptions: <unencodable>")
          }
        } else {
          Logger.info("providerOptions: <nil>")
        }
        return params
      })

      let wrappedModel = wrapLanguageModel(
        model: try openai("gpt-4o"),
        middleware: .single(logMiddleware)
      )

      let providerOptions: ProviderOptions = [
        "myMiddleware": [
          "example": .string("value")
        ]
      ]

      let result = try await generateText(
        model: wrappedModel,
        prompt: "Invent a new holiday and describe its traditions.",
        providerOptions: providerOptions
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func encodeProviderOptions(_ options: ProviderOptions) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(options)
      return String(data: data, encoding: .utf8)
    } catch {
      return nil
    }
  }
}
