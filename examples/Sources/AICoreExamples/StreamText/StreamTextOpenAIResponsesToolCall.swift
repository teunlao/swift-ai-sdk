import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesToolCallExample: Example {
  static let name = "stream-text/openai-responses-tool-call"
  static let description = "Demonstrates OpenAI Responses tool calling with sequential steps and parallelToolCalls disabled."

  private struct EmptyInput: Codable, Sendable {}
  private struct LocationResponse: Codable, Sendable { let location: String }
  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  static func run() async throws {
    do {
      let currentLocationTool: TypedTool<EmptyInput, LocationResponse> = tool(
        description: "Get the current location.",
        inputSchema: .auto(EmptyInput.self)
      ) { _, _ in
        let locations = ["New York", "London", "Paris", "Rome", "Tokyo"]
        let choice = locations.randomElement() ?? "New York"
        return LocationResponse(location: choice)
      }

      let weatherTool: TypedTool<WeatherQuery, WeatherReport> = tool(
        description: "Get the weather for a location",
        inputSchema: .auto(WeatherQuery.self)
      ) { input, _ in
        let temp = Int.random(in: 55...85)
        return WeatherReport(location: input.location, temperatureFahrenheit: temp)
      }

      let result = try streamText(
        model: openai.responses("gpt-4o-mini"),
        prompt: "What is the weather in my current location and in Rome?",
        tools: [
          "currentLocation": currentLocationTool.tool,
          "weather": weatherTool.tool
        ],
        providerOptions: openai.options.responses(parallelToolCalls: false),
        stopWhen: [stepCountIs(5)]
      )

      for try await part in result.fullStream {
        switch part {
        case .textDelta(_, let delta, _):
          print(delta, terminator: "")

        case .toolCall(let call):
          Logger.section("TOOL CALL \(call.toolName)")
          Helpers.printJSON(call.input)

        case .toolResult(let result):
          Logger.section("TOOL RESULT \(result.toolName)")
          Helpers.printJSON(result.output)

        case .finishStep(_, let usage, let finishReason, _):
          Logger.section("STEP FINISH")
          Logger.info("Finish reason: \(finishReason.rawValue)")
          Helpers.printJSON(usage)
          print("")

        case .finish(let finishReason, let totalUsage):
          Logger.section("FINISH")
          Logger.info("Finish reason: \(finishReason.rawValue)")
          Helpers.printJSON(totalUsage)

        case .error(let error):
          Logger.error(error.localizedDescription)

        default:
          continue
        }
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
