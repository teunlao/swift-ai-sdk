import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIOutputObjectExample: Example {
  static let name = "generate-text/openai-output-object"
  static let description = "Structured output + tool call using OpenAI GPT-4o mini."

  struct WeatherQuery: Codable, Sendable { let location: String }
  struct WeatherReport: Codable, Sendable {
    let location: String
    let temperature: Int
  }

  static func run() async throws {
    let weatherTool = tool(
      description: "Get the weather in a location",
      inputSchema: WeatherQuery.self
    ) { query, _ in
      WeatherReport(
        location: query.location,
        temperature: Int.random(in: 62...82)
      )
    }

    do {
      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        tools: ["weather": weatherTool.tool],
        prompt: "What is the weather in San Francisco?",
        stopWhen: [stepCountIs(2)],
        experimentalOutput: Output.object(WeatherReport.self, name: "weather")
      )

      Logger.section("Structured Output")
      let output = try result.experimentalOutput
      Helpers.printJSON(output)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
