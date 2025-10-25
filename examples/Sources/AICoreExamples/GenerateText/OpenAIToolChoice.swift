import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolChoiceExample: Example {
  static let name = "generate-text/openai-tool-choice"
  static let description = "Demonstrates toolChoice forcing the weather tool."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  private struct CityAttractionsQuery: Codable, Sendable { let city: String }
  private struct CityAttractions: Codable, Sendable { let attractions: [String] }

  static func run() async throws {
    let weatherTool = tool(
      description: "Get the weather in a location",
      inputSchema: WeatherQuery.self
    ) { query, _ in
      WeatherReport(
        location: query.location,
        temperatureFahrenheit: Int.random(in: 62...82)
      )
    }

    let cityAttractionsTool = tool(
      description: "List top attractions for a city",
      inputSchema: CityAttractionsQuery.self
    ) { query, _ in
      CityAttractions(attractions: [
        "Historic downtown tour in \(query.city)",
        "Local food market",
        "Museum district",
      ])
    }

    do {
      let result = try await generateText(
        model: openai("gpt-4.1-mini"),
        tools: [
          "weather": weatherTool.tool,
          "cityAttractions": cityAttractionsTool.tool,
        ],
        toolChoice: .tool(toolName: "weather"),
        prompt: "What is the weather in San Francisco and what attractions should I visit?",
        settings: CallSettings(maxOutputTokens: 512)
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Tool Calls")
      Logger.info(String(describing: result.toolCalls))
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
