import AISDKJSONSchema
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIStoreGenerationExample: Example {
  static let name = "stream-object/openai-store-generation"
  static let description = "Streams partial objects while enabling OpenAI response storage."

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
          "openai": [
            "store": true,
            "metadata": ["custom": "value"]
          ]
        ]
      )

      for try await partial in stream.partialObjectStream {
        Logger.section("Partial Object")
        Helpers.printJSON(partial)
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
