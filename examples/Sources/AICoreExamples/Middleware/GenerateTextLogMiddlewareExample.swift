import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct MiddlewareGenerateTextLogMiddlewareExample: Example {
  static let name = "middleware/generate-text-log-middleware-example"
  static let description = "Wrap generateText with a custom logging middleware."

  static func run() async throws {
    do {
      _ = try await generateText(
        model: wrapLanguageModel(
          model: openai("gpt-4o"),
          middleware: .single(yourLogMiddleware)
        ),
        prompt: "What cities are in the United States?"
      )
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

