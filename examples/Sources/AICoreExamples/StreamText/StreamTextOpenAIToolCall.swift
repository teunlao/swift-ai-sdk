import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIToolCallExample: Example {
  static let name = "stream-text/openai-tool-call"
  static let description = "Basic tool() usage in streamText without approval."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable { let location: String; let temperatureFahrenheit: Int }

  static func run() async throws {
    do {
      let weather: TypedTool<WeatherQuery, WeatherReport> = tool(
        description: "Get the weather in a location",
        inputSchema: .auto(WeatherQuery.self)
      ) { (input, _) in
        WeatherReport(location: input.location, temperatureFahrenheit: Int.random(in: 60...80))
      }

      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Use the weather tool to get the weather for San Francisco.",
        tools: ["weather": weather.tool]
      )

      for try await part in result.fullStream {
        switch part {
        case .toolCall(let call):
          Logger.info("toolCall: \(call.toolName)")
        case .toolResult(let res):
          if res.toolName == "weather" {
            let report = try weather.decodeOutput(from: res)
            Logger.info("report: \(report.temperatureFahrenheit)°F in \(report.location)")
          }
        case .textDelta(_, let delta, _):
          print(delta, terminator: "")
        default:
          break
        }
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

