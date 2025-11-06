import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIReadUIMessageStreamExample: Example {
  static let name = "stream-text/openai-read-ui-message-stream"
  static let description = "Convert stream to UI message stream and print chunk types."

  static func run() async throws {
    do {
      let result = try streamText(
        model: try openai("gpt-4o"),
        prompt: "Explain in two sentences what Swift AI SDK does."
      )

      let uiStream = result.toUIMessageStream(options: UIMessageStreamOptions<UIMessage>())
      for try await chunk in uiStream {
        Logger.info(String(describing: chunk))
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

