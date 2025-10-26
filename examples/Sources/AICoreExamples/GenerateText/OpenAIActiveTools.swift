import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIActiveToolsExample: Example {
  static let name = "generate-text/openai-active-tools"
  static let description = "Shows how to disable tools for a call using activeTools = []."

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
        "Museum district in \(query.city)",
        "Historic old town",
        "Local food market"
      ])
    }

    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let result = try await generateText(
        model: openai("gpt-4o"),
        tools: [
          "weather": weatherTool.tool,
          "cityAttractions": cityAttractionsTool.tool
        ],
        prompt: "What is the weather in San Francisco and what attractions should I visit?",
        stopWhen: [stepCountIs(5)],
        activeTools: [] // disables all tools for this request
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
