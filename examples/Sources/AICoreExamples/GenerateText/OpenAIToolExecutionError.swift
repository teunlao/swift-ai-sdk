import Foundation
import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIToolExecutionErrorExample: Example {
  static let name = "generate-text/openai-tool-execution-error"
  static let description = "Demonstrates how tool execution failures surface in responses."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  private enum WeatherToolError: LocalizedError {
    case failed(location: String)

    var errorDescription: String? {
      switch self {
      case let .failed(location):
        return "Could not get weather for \(location)."
      }
    }
  }

  static func run() async throws {
    let failingWeatherTool = tool(
      description: "Get the weather in a location (fails intentionally)",
      inputSchema: WeatherQuery.self
    ) { query, _ -> WeatherReport in
      throw WeatherToolError.failed(location: query.location)
    }

    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      let _ = apiKey

      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        tools: ["weather": failingWeatherTool.tool],
        prompt: "What is the weather in San Francisco?",
        settings: CallSettings(maxOutputTokens: 256)
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Tool Errors")
      for (index, step) in result.steps.enumerated() {
        for part in step.content {
          if case let .toolError(error, _) = part {
            Logger.info("Step #\(index) tool-error from \(error.toolName): \(error.error.localizedDescription)")
          }
        }
      }

      Logger.section("Response Messages")
      for message in result.response.messages {
        switch message {
        case .assistant(let assistant):
          switch assistant.content {
          case .text(let text):
            Logger.info("assistant: \(text)")
          case .parts(let parts):
            Logger.info("assistant parts count: \(parts.count)")
          }

        case .tool(let toolMessage):
          Logger.info("tool message with \(toolMessage.content.count) part(s)")
        }
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
