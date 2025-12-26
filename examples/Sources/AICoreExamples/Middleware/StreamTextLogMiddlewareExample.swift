import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct MiddlewareStreamTextLogMiddlewareExample: Example {
  static let name = "middleware/stream-text-log-middleware"
  static let description = "Wrap streamText with a custom logging middleware."

  static func run() async throws {
    do {
      let result = try streamText(
        model: wrapLanguageModel(
          model: openai("gpt-4o"),
          middleware: .single(yourLogMiddleware)
        ),
        prompt: "What cities are in the United States?"
      )

      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

