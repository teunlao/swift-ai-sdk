import ExamplesCore
import Foundation
import OpenAIProvider
import AISDKProvider
import SwiftAISDK

struct GenerateTextOpenAIFullResultExample: Example {
  static let name = "generate-text/openai-full-result"
  static let description = "Serializes the complete generateText result for inspection."

  static func run() async throws {
    do {
      try EnvLoader.load()

      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        prompt: "Invent a new holiday and describe its traditions."
      )

      Logger.section("Full Result (JSON)")
      let json = try result.jsonString()
      print(json)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
