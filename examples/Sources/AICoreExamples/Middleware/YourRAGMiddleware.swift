import Foundation
import SwiftAISDK

let yourRagMiddleware: LanguageModelV3Middleware = LanguageModelV3Middleware(
  transformParams: { _, params, _ in
    guard let lastUserMessageText = getLastUserMessageText(prompt: params.prompt) else {
      return params
    }

    let sources = findSources(text: lastUserMessageText)
    let instruction =
      "Use the following information to answer the question:\n"
      + sources.map { encodeJSONLine($0) }.joined(separator: "\n")

    return addToLastUserMessage(text: instruction, params: params)
  }
)

private struct SourceChunk: Codable, Sendable {
  let title: String
  let previewText: String?
  let url: String?
}

private func findSources(text: String) -> [SourceChunk] {
  [
    SourceChunk(
      title: "New York",
      previewText: "New York is a city in the United States.",
      url: "https://en.wikipedia.org/wiki/New_York"
    ),
    SourceChunk(
      title: "San Francisco",
      previewText: "San Francisco is a city in the United States.",
      url: "https://en.wikipedia.org/wiki/San_Francisco"
    ),
  ]
}

private func encodeJSONLine<T: Encodable>(_ value: T) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
    return "{}"
  }
  return string
}
