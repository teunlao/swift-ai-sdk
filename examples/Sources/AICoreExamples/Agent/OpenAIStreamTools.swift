import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct AgentOpenAIStreamToolsExample: Example {
  static let name = "agent/openai-stream-tools"
  static let description = "Stream agent output while it calls a weather tool."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable { let location: String; let temperature: Int }

  static func run() async throws {
    do {
      let weather: TypedTool<WeatherQuery, WeatherReport> = tool(
        description: "Get the weather in a location",
        inputSchema: .auto(WeatherQuery.self)
      ) { input, _ in
        WeatherReport(location: input.location, temperature: Int.random(in: 62...82))
      }

      let model = try openai("gpt-5")
      let settings = BasicAgentSettings(
        system: "You are a helpful assistant that answers questions about the weather.",
        model: model,
        tools: ["weather": weather.tool]
      )
      let agent = BasicAgent(settings: settings)

      let result = try agent.stream(prompt: Prompt.text("What is the weather in Tokyo?"))
      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
