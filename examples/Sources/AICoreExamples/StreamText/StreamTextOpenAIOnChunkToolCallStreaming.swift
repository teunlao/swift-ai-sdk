import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct StreamTextOpenAIOnChunkToolCallStreamingExample: Example {
  static let name = "stream-text/openai-on-chunk-tool-call-streaming"
  static let description = "Stream tool call inputs/outputs via onChunk while text streams."

  private struct WeatherQuery: Codable, Sendable { let location: String }
  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
  }

  static func run() async throws {
    do {
      // Typed tool that returns a simple weather report.
      let weather: TypedTool<WeatherQuery, WeatherReport> = tool(
        description: "Get the weather in a location",
        inputSchema: .auto(WeatherQuery.self)
      ) { (input, _) in
        // Simulate external call
        try await Task.sleep(nanoseconds: 200_000_000)
        return WeatherReport(location: input.location, temperatureFahrenheit: Int.random(in: 60...80))
      }

      Logger.section("Streaming with tool call chunks")
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "Use the weather tool to get the weather for San Francisco and summarize it in one sentence.",
        tools: ["weather": weather.tool],
        onChunk: { part in
          switch part {
          case .toolInputStart(let id, let toolName, _, _, _):
            Logger.info("toolInputStart id=\(id) tool=\(toolName)")
          case .toolInputDelta(let id, let delta, _):
            Logger.info("toolInputDelta id=\(id) delta=\(delta.prefix(60))...")
          case .toolInputEnd(let id, _):
            Logger.info("toolInputEnd id=\(id)")
          case .toolCall(let call):
            Logger.info("toolCall name=\(call.toolName) id=\(call.toolCallId)")
          case .toolResult(let result):
            Logger.info("toolResult id=\(result.toolCallId) output=\(result.output)")
          default:
            break
          }
        },
        onFinish: { finalStep, _, usage, reason in
          Logger.section("Finish")
          Logger.info("finishReason: \(reason)")
          Logger.info("totalTokens: \(usage.totalTokens ?? 0)")
        }
      )

      // Drain text stream to drive the pipeline
      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
