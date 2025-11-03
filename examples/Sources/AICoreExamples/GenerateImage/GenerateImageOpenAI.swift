import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateImageOpenAIExample: Example {
  static let name = "generate-image/openai"
  static let description = "Generate an image with OpenAI gpt-image-1-mini and save to a file."

  static func run() async throws {
    let prompt = "Santa Claus driving a Cadillac"
    Logger.section("Prompt")
    Logger.info(prompt)

    do {
      let result = try await generateImage(
        model: openai.image("gpt-image-1-mini"),
        prompt: prompt
      )

      // Извлечём revisedPrompt из providerMetadata (если есть)
      if let openAIMeta = result.providerMetadata["openai"],
         let first = openAIMeta.images.first,
         case let .object(obj) = first,
         case let .string(revised)? = obj["revisedPrompt"] {
        Logger.section("Revised Prompt")
        Logger.info(revised)
      }

      Logger.section("Image Info")
      Logger.info("mediaType: \(result.image.mediaType)")

      // Сохраним картинку во временный файл
      let ext: String = {
        switch result.image.mediaType.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/webp": return "webp"
        default: return "png"
        }
      }()

      let fileURL = try Helpers.createTempFile(data: result.image.data, extension: ext)
      Logger.success("Saved → \(fileURL.path)")

    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
