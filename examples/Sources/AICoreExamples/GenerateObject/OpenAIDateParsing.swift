import Foundation
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateObjectOpenAIDateParsingExample: Example {
  static let name = "generate-object/openai-date-parsing"
  static let description = "Parses ISO8601 date strings from OpenAI into `Date`."

  struct Event: Codable, Sendable {
    let date: String
    let event: String
  }

  struct Response: Codable, Sendable {
    let events: [Event]
  }

  static func run() async throws {
    do {
      let result = try await generateObject(
        model: openai("gpt-4o"),
        schema: Response.self,
        prompt: "List exactly 5 JSON objects with `date` (YYYY-MM-DD) and `event` for notable moments in the year 2000.",
        mode: .json,
        settings: CallSettings(temperature: 0)
      )

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withFullDate]

      Logger.section("Events")
      result.object.events.forEach { event in
        if formatter.date(from: event.date) != nil {
          Logger.info("\(event.date): \(event.event)")
        } else {
          Logger.warning("Could not parse date: \(event.date)")
        }
      }

      Logger.section("Token usage")
      Helpers.printJSON(result.usage)

      Logger.section("Finish reason")
      Logger.info(result.finishReason.rawValue)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
