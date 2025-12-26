import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct MiddlewareSimulateStreamingExample: Example {
  static let name = "middleware/simulate-streaming-example"
  static let description = "Simulate streaming chunks using simulateStreamingMiddleware()."

  static func run() async throws {
    do {
      let result = try streamText(
        model: wrapLanguageModel(
          model: openai("gpt-4o"),
          middleware: .single(simulateStreamingMiddleware())
        ),
        prompt: "What cities are in the United States?"
      )

      for try await chunk in result.textStream {
        print(chunk)
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
