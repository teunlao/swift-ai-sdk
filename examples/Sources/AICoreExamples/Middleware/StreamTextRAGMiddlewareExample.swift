import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct MiddlewareStreamTextRAGMiddlewareExample: Example {
  static let name = "middleware/stream-text-rag-middleware"
  static let description = "Augment the last user message via a simple RAG middleware."

  static func run() async throws {
    do {
      let result = try streamText(
        model: wrapLanguageModel(
          model: openai("gpt-4o"),
          middleware: .single(yourRagMiddleware)
        ),
        prompt: "What cities are in the United States?"
      )

      for try await textPart in result.textStream {
        print(textPart, terminator: "")
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

