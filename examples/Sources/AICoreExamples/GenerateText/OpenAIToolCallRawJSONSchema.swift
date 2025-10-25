import Foundation
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolCallRawJSONSchemaExample: Example {
  static let name = "generate-text/openai-tool-call-raw-json-schema"
  static let description = "Defines tool schemas manually via JSON Schema instead of Codable auto()."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  private struct CityAttractionsQuery: Codable, Sendable { let city: String }

  static func run() async throws {
    let weatherSchemaJSON: JSONValue = [
      "type": "object",
      "properties": [
        "location": ["type": "string"]
      ],
      "required": ["location"]
    ]

    let citySchemaJSON: JSONValue = [
      "type": "object",
      "properties": [
        "city": ["type": "string"]
      ],
      "required": ["city"]
    ]

    let weatherSchema = FlexibleSchema(
      Schema.codable(WeatherQuery.self, jsonSchema: weatherSchemaJSON)
    )

    let citySchema = FlexibleSchema(
      Schema.codable(CityAttractionsQuery.self, jsonSchema: citySchemaJSON)
    )

    let weatherTool = tool(
      description: "Get the weather in a location",
      inputSchema: weatherSchema
    ) { query, _ in
      WeatherReport(
        location: query.location,
        temperatureFahrenheit: Int.random(in: 62...82)
      )
    }

    let cityAttractionsTool: TypedTool<CityAttractionsQuery, JSONValue> = tool(
      description: "List top attractions for a city",
      inputSchema: citySchema
    )

    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      let _ = apiKey

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
            Logger.info("Weather tool input: \(input.location)")
          case "cityAttractions":
            let input = try await cityAttractionsTool.decodeInput(from: call)
            Logger.info("City attractions input: \(input.city)")
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
            Logger.info("City attractions tool returned no result (no execute handler)")
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
