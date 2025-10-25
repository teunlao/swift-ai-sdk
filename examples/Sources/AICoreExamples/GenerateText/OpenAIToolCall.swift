import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolCallExample: Example {
  static let name = "generate-text/openai-tool-call"
  static let description = "Inspect typed tool calls and results returned by the model."

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
        "Historic downtown walking tour in \(query.city)",
        "Local food hall",
        "Museum quarter"
      ])
    }

    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        tools: [
          "weather": weatherTool.tool,
          "cityAttractions": cityAttractionsTool.tool
        ],
        prompt: "What is the weather in San Francisco and what attractions should I visit?",
        settings: CallSettings(maxOutputTokens: 512)
      )

      Logger.section("Tool Calls")
      for call in result.toolCalls {
        switch call {
        case .dynamic:
          Logger.info("Dynamic tool call encountered; skipping typed decoding")

        case .static(let staticCall):
          switch staticCall.toolName {
          case "weather":
            let input = try await weatherTool.decodeInput(from: call)
            Logger.info("Weather tool invoked for location: \(input.location)")

          case "cityAttractions":
            let input = try await cityAttractionsTool.decodeInput(from: call)
            Logger.info("City attractions requested for: \(input.city)")

          default:
            Logger.info("Unhandled tool call: \(staticCall.toolName)")
          }
        }
      }

      Logger.section("Tool Results")
      for toolResult in result.toolResults {
        switch toolResult {
        case .dynamic:
          Logger.info("Dynamic tool result encountered; skipping typed decoding")

        case .static(let staticResult):
          switch staticResult.toolName {
          case "weather":
            let output = try weatherTool.decodeOutput(from: toolResult)
            Logger.info("Weather report: \(output.location) -> \(output.temperatureFahrenheit)°F")

          case "cityAttractions":
            let attractions = try cityAttractionsTool.decodeOutput(from: toolResult)
            Logger.info("Attractions returned: \(attractions.attractions.joined(separator: ", "))")

          default:
            Logger.info("Unhandled tool result: \(staticResult.toolName)")
          }
        }
      }

      Logger.section("Assistant Text")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
