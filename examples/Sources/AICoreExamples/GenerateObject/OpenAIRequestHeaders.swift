import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIRequestHeadersExample: Example {
  static let name = "generate-object/openai-request-headers"
  static let description = "Inspect the HTTP headers sent to OpenAI."

  struct Ingredient: Codable, Sendable {
    let name: String
    let amount: String
  }

  struct Recipe: Codable, Sendable {
    let name: String
    let ingredients: [Ingredient]
    let steps: [String]
  }

  struct Response: Codable, Sendable {
    let recipe: Recipe
  }

  actor HeaderStore {
    private var headers: [String: String]?

    func record(_ headers: [String: String]?) {
      self.headers = headers
    }

    func value() -> [String: String]? {
      headers
    }
  }

  static func run() async throws {
    do {
      let store = HeaderStore()

      let inspectFetch: FetchFunction = { request in
        let sanitized = Self.sanitize(headers: request.allHTTPHeaderFields ?? [:])
        await store.record(sanitized.isEmpty ? nil : sanitized)

        let session = URLSession.shared
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
          let (data, response) = try await session.data(for: request)
          return FetchResponse(body: data.isEmpty ? .none : .data(data), urlResponse: response)
        } else {
          let (data, response) = try await session.data(for: request)
          return FetchResponse(body: data.isEmpty ? .none : .data(data), urlResponse: response)
        }
      }

      let openAI = createOpenAIProvider(settings: .init(fetch: inspectFetch))

      let result = try await generateObject(
        model: try openAI("gpt-4o-mini"),
        schema: Response.self,
        prompt: "Generate a lasagna recipe."
      )

      Logger.section("Request headers")
      if let headers = await store.value() {
        Helpers.printJSON(headers)
      } else {
        Logger.info("<no headers>")
      }

      Logger.section("Recipe name")
      Logger.info(result.object.recipe.name)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func sanitize(headers: [String: String]) -> [String: String] {
    headers.reduce(into: [:]) { result, pair in
      let (key, value) = pair
      if key.lowercased().contains("authorization") {
        result[key] = Self.mask(value)
      } else {
        result[key] = value
      }
    }
  }

  private static func mask(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 12 else { return "<redacted>" }
    let prefix = trimmed.prefix(6)
    let suffix = trimmed.suffix(4)
    return "\(prefix)…\(suffix)"
  }
}
