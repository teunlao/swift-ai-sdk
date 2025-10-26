import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAICustomHeadersExample: Example {
  static let name = "generate-text/openai-custom-headers"
  static let description = "Demonstrates provider-level and per-request headers with OpenAI."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let loggingFetch: FetchFunction = { request in
        Logger.section("Custom Fetch: Headers")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
          let sanitizedPairs = headers.map { key, value in
            (key, Self.maskSensitiveHeader(name: key, value: value))
          }
          Helpers.printJSON(Dictionary(uniqueKeysWithValues: sanitizedPairs))
        } else {
          Logger.info("Headers: <none>")
        }

        let session = URLSession.shared
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
          let (data, response) = try await session.data(for: request)
          return FetchResponse(body: data.isEmpty ? .none : .data(data), urlResponse: response)
        } else {
          let (data, response) = try await session.data(for: request)
          return FetchResponse(body: data.isEmpty ? .none : .data(data), urlResponse: response)
        }
      }

      let customProvider = createOpenAIProvider(
        settings: OpenAIProviderSettings(
          apiKey: apiKey,
          headers: ["custom-provider-header": "value-1"],
          fetch: loggingFetch
        )
      )

      let result = try await generateText(
        model: try customProvider("gpt-4o-mini"),
        prompt: "Invent a new holiday and describe its traditions.",
        settings: CallSettings(
          maxOutputTokens: 50,
          headers: ["custom-request-header": "value-2"]
        )
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func maskSensitiveHeader(name: String, value: String) -> String {
    let lowercased = name.lowercased()
    if lowercased.contains("authorization") || lowercased.contains("api-key") {
      let trimmed = value.trimmingCharacters(in: .whitespaces)
      guard trimmed.count > 12 else { return "<redacted>" }
      let prefix = trimmed.prefix(6)
      let suffix = trimmed.suffix(4)
      return "\(prefix)…\(suffix)"
    }
    return value
  }
}
