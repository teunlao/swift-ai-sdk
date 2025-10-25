import Foundation
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolCallWithContextExample: Example {
  static let name = "generate-text/openai-tool-call-with-context"
  static let description = "Passes experimentalContext into tool execution and decodes it."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  private struct WeatherContext: Codable, Sendable {
    let weatherApiKey: String
  }

  static func run() async throws {
    let weatherTool = tool(
      description: "Get the weather in a location",
      inputSchema: WeatherQuery.self
    ) { query, options in
      let context = try options.decodeExperimentalContext(WeatherContext.self)
      Logger.info("Weather tool received context key prefix: \(context.weatherApiKey.prefix(3))...")

      return WeatherReport(
        location: query.location,
        temperatureFahrenheit: Int.random(in: 62...82)
      )
    }

    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      let _ = apiKey

      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        tools: ["weather": weatherTool.tool],
        prompt: "What is the weather in San Francisco?",
        experimentalContext: .object(["weatherApiKey": .string("123")])
      )

      Logger.section("Tool Calls")
      for call in result.toolCalls {
        Logger.info("tool call: \(call.toolName)")
      }

      Logger.section("Tool Results")
      for toolResult in result.toolResults {
        switch toolResult {
        case .static(let staticResult):
          let decoded = try weatherTool.decodeOutput(from: toolResult)
          Logger.info("Weather output: \(decoded.location) -> \(decoded.temperatureFahrenheit)°F")
          Logger.info("Provider metadata: \(String(describing: staticResult.providerMetadata))")
        case .dynamic(let dynamicResult):
          Logger.info("Dynamic tool result: \(dynamicResult.toolName)")
        }
      }

      Logger.section("Assistant Text")
      Logger.info(result.text)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
