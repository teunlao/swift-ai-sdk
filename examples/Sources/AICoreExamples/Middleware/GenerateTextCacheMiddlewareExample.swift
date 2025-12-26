import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct MiddlewareGenerateTextCacheMiddlewareExample: Example {
  static let name = "middleware/generate-text-cache-middleware-example"
  static let description = "Cache generateText results in middleware to speed up repeated calls."

  static func run() async throws {
    do {
      let baseModel = try openai("gpt-4o")
      let modelWithCaching = wrapLanguageModel(model: baseModel, middleware: .single(yourCacheMiddleware))

      let start1 = Date()
      let result1 = try await generateText(
        model: modelWithCaching,
        prompt: "What cities are in the United States?"
      )
      let end1 = Date()

      let start2 = Date()
      let result2 = try await generateText(
        model: modelWithCaching,
        prompt: "What cities are in the United States?"
      )
      let end2 = Date()

      Logger.info("Time taken for result1: \(Helpers.formatDuration(end1.timeIntervalSince(start1)))")
      Logger.info("Time taken for result2: \(Helpers.formatDuration(end2.timeIntervalSince(start2)))")
      Logger.info("Same text: \(result1.text == result2.text)")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
