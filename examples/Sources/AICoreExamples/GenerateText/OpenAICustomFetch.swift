import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAICustomFetchExample: Example {
  static let name = "generate-text/openai-custom-fetch"
  static let description = "Wrap the OpenAI fetch implementation to inspect outgoing requests."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let loggingFetch: FetchFunction = { request in
        Logger.section("Custom Fetch: Request")
        Logger.info("URL: \(request.url?.absoluteString ?? "<nil>")")

        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
          let sanitized = Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key, Self.maskSensitiveHeader(name: key, value: value))
          })
          Helpers.printJSON(sanitized)
        } else {
          Logger.info("Headers: <none>")
        }

        if let bodyData = request.httpBody, !bodyData.isEmpty {
          if let jsonObject = try? JSONSerialization.jsonObject(with: bodyData),
             JSONSerialization.isValidJSONObject(jsonObject),
             let pretty = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
             let jsonString = String(data: pretty, encoding: .utf8) {
            Logger.info("Body (JSON):\n\(jsonString)")
          } else if let bodyString = String(data: bodyData, encoding: .utf8) {
            Logger.info("Body (text):\n\(bodyString)")
          } else {
            Logger.info("Body: <binary data, \(bodyData.count) bytes>")
          }
        } else if request.httpBodyStream != nil {
          Logger.info("Body: <streamed – not logged>")
        } else {
          Logger.info("Body: <empty>")
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

      let customOpenAI = createOpenAIProvider(settings: OpenAIProviderSettings(fetch: loggingFetch))

      let result = try await generateText(
        model: try customOpenAI("gpt-4o-mini"),
        prompt: "Invent a new holiday and describe its traditions."
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
