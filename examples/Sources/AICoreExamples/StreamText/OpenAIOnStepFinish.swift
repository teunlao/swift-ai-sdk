import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIOnStepFinishExample: Example {
  static let name = "stream-text/openai-on-step-finish"
  static let description = "Log each step via onStepFinish with a local weather tool."

  struct WeatherQuery: Codable, Sendable { let location: String }
  struct WeatherReport: Codable, Sendable { let temperature: Int }

  static func run() async throws {
    let weather = tool(
      description: "Get the weather in a location",
      inputSchema: WeatherQuery.self,
      execute: { (_: WeatherQuery, _) in
        WeatherReport(temperature: Int.random(in: 62...82))
      }
    )

    do {
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "What is the current weather in San Francisco?",
        tools: ["weather": weather.tool],
        stopWhen: [stepCountIs(5)],
        onStepFinish: { step in
          Logger.section("Step Finished")
          Logger.info("finishReason=\(step.finishReason)")
          Logger.info("usage.total=\(step.usage.totalTokens ?? 0)")
          if !step.toolCalls.isEmpty {
            Logger.info("toolCalls=\(step.toolCalls.count)")
          }
          if !step.toolResults.isEmpty {
            Logger.info("toolResults=\(step.toolResults.count)")
          }
          if !step.text.isEmpty {
            Logger.info("text=\(Helpers.truncate(step.text, to: 200))")
          }
        }
      )

      // Drain text stream (output is not printed to reduce noise)
      for try await _ in result.textStream { }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
