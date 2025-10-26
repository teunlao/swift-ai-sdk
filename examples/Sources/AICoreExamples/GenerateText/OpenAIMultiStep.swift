import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIMultiStepExample: Example {
  static let name = "generate-text/openai-multi-step"
  static let description = "Demonstrates multi-step tool calling with per-step logging." 

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let currentLocationTool = tool(
        description: "Get the current location.",
        inputSchema: EmptyInput.self
      ) { _, _ in
        let locations = ["New York", "London", "Paris"]
        return CurrentLocation(location: locations.randomElement() ?? "New York")
      }

      let weatherTool = tool(
        description: "Get the weather in a location",
        inputSchema: WeatherQuery.self
      ) { query, _ in
        WeatherReport(
          location: query.location,
          temperature: 72 + Int.random(in: -10...10)
        )
      }

      let stepCounter = StepCounter()

      let result = try await generateText(
        model: openai("gpt-4o-2024-08-06"),
        tools: [
          "currentLocation": currentLocationTool.tool,
          "weather": weatherTool.tool
        ],
        prompt: "What is the weather in my current location?",
        stopWhen: [stepCountIs(5)],
        onStepFinish: { step in
          let index = await stepCounter.next()
          Logger.section("Step \(index)")
          if let json = encodeStep(step, index: index) {
            Logger.info(json)
          }
        }
      )

      Logger.section("Final Text")
      Logger.info(result.text)

      Logger.section("Usage")
      Helpers.printJSON(result.totalUsage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private struct EmptyInput: Codable, Sendable {}

  private struct CurrentLocation: Codable, Sendable {
    let location: String
  }

  private struct WeatherQuery: Codable, Sendable {
    let location: String
  }

  private struct WeatherReport: Codable, Sendable {
    let location: String
    let temperature: Int
  }

  private actor StepCounter {
    private var value = 0

    func next() -> Int {
      value += 1
      return value
    }
  }

  private struct StepLog: Encodable {
    struct ToolCallLog: Encodable {
      let toolCallId: String
      let toolName: String
      let input: JSONValue
      let providerExecuted: Bool?
      let providerMetadata: ProviderMetadata?
      let dynamic: Bool
      let invalid: Bool?
    }

    struct ToolResultLog: Encodable {
      let toolCallId: String
      let toolName: String
      let input: JSONValue
      let output: JSONValue
      let providerExecuted: Bool?
      let preliminary: Bool?
      let providerMetadata: ProviderMetadata?
      let dynamic: Bool
    }

    struct ReasoningLog: Encodable {
      let text: String
      let providerMetadata: ProviderMetadata?
    }

    let index: Int
    let finishReason: FinishReason
    let text: String
    let reasoning: [ReasoningLog]
    let toolCalls: [ToolCallLog]
    let toolResults: [ToolResultLog]
    let usage: LanguageModelUsage
    let warnings: [CallWarning]?
    let providerMetadata: ProviderMetadata?
  }

  private static func encodeStep(_ step: StepResult, index: Int) -> String? {
    let toolCalls = step.toolCalls.map { call -> StepLog.ToolCallLog in
      StepLog.ToolCallLog(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        input: call.input,
        providerExecuted: call.providerExecuted,
        providerMetadata: call.providerMetadata,
        dynamic: call.isDynamic,
        invalid: call.invalid
      )
    }

    let toolResults = step.toolResults.map { result -> StepLog.ToolResultLog in
      StepLog.ToolResultLog(
        toolCallId: result.toolCallId,
        toolName: result.toolName,
        input: result.input,
        output: result.output,
        providerExecuted: result.providerExecuted,
        preliminary: result.preliminary,
        providerMetadata: result.providerMetadata,
        dynamic: result.isDynamic
      )
    }

    let reasoning = step.reasoning.map { output in
      StepLog.ReasoningLog(text: output.text, providerMetadata: output.providerMetadata)
    }

    let log = StepLog(
      index: index,
      finishReason: step.finishReason,
      text: step.text,
      reasoning: reasoning,
      toolCalls: toolCalls,
      toolResults: toolResults,
      usage: step.usage,
      warnings: step.warnings,
      providerMetadata: step.providerMetadata
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
      let data = try encoder.encode(log)
      return String(data: data, encoding: .utf8)
    } catch {
      Logger.warning("Failed to encode step \(index): \(error)")
      return nil
    }
  }
}
