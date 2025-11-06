import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIMultimodalExample: Example {
  static let name = "generate-object/openai-multimodal"
  static let description = "Structured image response using GPT-4o."

  struct Artwork: Codable, Sendable {
    let description: String
    let style: String
    let review: String
  }

  struct Response: Codable, Sendable {
    let artwork: Artwork
  }

  static func run() async throws {
    do {
      let imageData = try loadImage()

      let messages: [ModelMessage] = [
        .user(
          UserModelMessage(
            content: .parts([
              .text(TextPart(text: "Describe the image in detail and review it")),
              .file(
                FilePart(
                  data: .data(imageData),
                  mediaType: "image/png",
                  filename: "comic-cat.png"
                )
              )
            ])
          )
        )
      ]

      let result = try await generateObject(
        model: openai("gpt-4o"),
        schema: Response.self,
        system: "You are an art critic reviewing a piece of art.",
        messages: messages
      )

      Logger.section("Artwork metadata")
      Helpers.printJSON(result.object.artwork)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func loadImage() throws -> Data {
    let fm = FileManager.default
    let baseURL = URL(fileURLWithPath: fm.currentDirectoryPath)
    let candidates = [
      baseURL.appendingPathComponent("Data/comic-cat.png"),
      baseURL.appendingPathComponent("examples/Data/comic-cat.png"),
      baseURL.appendingPathComponent("../Data/comic-cat.png"),
      baseURL.appendingPathComponent("../examples/Data/comic-cat.png")
    ]

    for candidate in candidates where fm.fileExists(atPath: candidate.path) {
      Logger.debug("Loading image from: \(candidate.path)")
      return try Data(contentsOf: candidate)
    }

    throw NSError(
      domain: "GenerateObjectOpenAIMultimodalExample",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "comic-cat.png not found. Copy it from external/vercel-ai-sdk/examples/ai-core/data into examples/Data."
      ]
    )
  }
}
