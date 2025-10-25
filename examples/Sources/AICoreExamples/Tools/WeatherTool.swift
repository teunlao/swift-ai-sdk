import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct WeatherToolExample: Example {
  struct WeatherQuery: Codable, Sendable { let location: String }
  struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  static let name = "tools/weather-tool"
  static let description = "the weather tool example."

  static func run() async throws {
    let weatherTool = tool(
      description: "Get the weather in a location",
      inputSchema: WeatherQuery.self,
      execute: { (query: WeatherQuery, _) in
        WeatherReport(
          location: query.location,
          temperatureFahrenheit: Int.random(in: 62...82)
        )
      }
    )

    Logger.section("Weather tool output (local execution)")
    let localResult = try await weatherTool.execute?(
      WeatherQuery(location: "San Francisco"),
      ToolCallOptions(toolCallId: "weather-call", messages: [])
    )

    if let report = try await localResult?.resolve() {
      Helpers.printJSON(report)
    } else {
      Logger.info("No result produced by tool")
    }

    Logger.success("Local weather tool run completed")

    do {
      try EnvLoader.load()
      Logger.section("Calling OpenAI with weather tool")

      let response = try await generateText(
        model: openai("gpt-4.1"),
        tools: ["weather": weatherTool.tool],
        prompt:
          "Use the weather tool to fetch the weather for San Francisco and summarize the result."
      )

      Logger.info("Model text: \(response.text)")

      if let toolResult = response.toolResults.first {
        let decoded = try weatherTool.decodeOutput(from: toolResult)
        Logger.section("Decoded tool result from OpenAI")
        Helpers.printJSON(decoded)
      } else {
        Logger.info("No tool result produced by the model")
      }
    } catch {
      Logger.warning("Skipping OpenAI call: \(error.localizedDescription)")
    }

    Logger.success("Weather tool example completed")
  }
}
