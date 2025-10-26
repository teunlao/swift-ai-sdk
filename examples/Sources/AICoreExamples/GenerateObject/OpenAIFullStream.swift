import AISDKJSONSchema
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIFullStreamExample: Example {
  static let name = "stream-object/openai-full-stream"
  static let description = "Streams structured data and prints full events (object/logprobs/usage)."

  struct Character: Codable, Sendable {
    let name: String
    let `class`: String
    let description: String
  }

  struct Response: Codable, Sendable {
    let characters: [Character]
  }

  static func run() async throws {
    do {
      let stream = try streamObject(
        model: .v3(openai("gpt-4o")),
        output: GenerateObjectOutput.object(
          schema: FlexibleSchema.auto(Response.self)
        ),
        prompt: "Generate 3 character descriptions for a fantasy role playing game.",
        providerOptions: [
          "openai": ["logprobs": 2]
        ],
        settings: CallSettings(maxOutputTokens: 2_000)
      )

      for try await part in stream.fullStream {
        switch part {
        case .object(let partial):
          Logger.section("Partial Object")
          Helpers.printJSON(partial)

        case .textDelta(let text):
          Logger.info("Text delta: \(text)")

        case .finish(let finish):
          Logger.section("Finish Reason")
          Logger.info(finish.finishReason.rawValue)

          Logger.section("Usage")
          Helpers.printJSON(finish.usage)

          if let logprobs = finish.providerMetadata?["openai"]?["logprobs"] {
            Logger.section("Logprobs")
            Helpers.printJSON(logprobs)
          }

        case .error(let error):
          Logger.error("Stream error: \(error)")
        }
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
