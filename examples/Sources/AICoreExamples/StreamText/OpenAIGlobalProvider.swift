import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIGlobalProviderExample: Example {
  static let name = "stream-text/openai-global-provider"
  static let description = "Stream text using the default global OpenAI provider instance."

  static func run() async throws {
    do {
      // The global `openai` instance is configured from environment (.env) and ready to use.
      let result = try streamText(
        model: openai("gpt-5-mini"),
        prompt: "Invent a new holiday and describe its traditions."
      )

      for try await chunk in result.textStream {
        print(chunk, terminator: "")
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

