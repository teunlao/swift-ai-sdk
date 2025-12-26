import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct MiddlewareDefaultSettingsExample: Example {
  static let name = "middleware/default-settings-example"
  static let description = "Apply default call settings via defaultSettingsMiddleware()."

  static func run() async throws {
    do {
      let model = wrapLanguageModel(
        model: openai.responses("gpt-4o"),
        middleware: .single(
          defaultSettingsMiddleware(
            settings: DefaultSettings(
              temperature: 0.5,
              providerOptions: openai.options.responses(store: false)
            )
          )
        )
      )

      let result = try await generateText(
        model: model,
        prompt: "What cities are in the United States?"
      )

      Logger.section("response.body")
      if let body = result.response.body {
        Helpers.printJSON(body)
      } else {
        Logger.info("<nil>")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
