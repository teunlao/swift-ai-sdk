import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesReasoningSummaryExample: Example {
  static let name = "stream-text/openai-responses-reasoning-summary"
  static let description = "Stream reasoning deltas and text using the OpenAI Responses reasoningSummary option."

  static func run() async throws {
    do {
      let providerOptions = openai.options.responses(
        reasoningSummary: "auto"
      )

      let result = try streamText(
        model: openai.responses("o3-mini"),
        system: "You are a helpful assistant.",
        prompt: "Tell me about the debate over Taqueria La Cumbre and El Farolito and who created the San Francisco Mission-style burrito.",
        providerOptions: providerOptions
      )

      for try await part in result.fullStream {
        switch part {
        case .reasoningDelta(_, let text, _):
          print("\u{001B}[34m\(text)\u{001B}[0m", terminator: "")
        case .textDelta(_, let text, _):
          print(text, terminator: "")
        default:
          break
        }
      }
      print("")

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)

      Logger.section("Provider metadata")
      if let metadata = try await result.providerMetadata {
        Helpers.printJSON(metadata)
      } else {
        Logger.info("<none>")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
