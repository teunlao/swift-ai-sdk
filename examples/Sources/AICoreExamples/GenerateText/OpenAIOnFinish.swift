import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIOnFinishExample: Example {
  static let name = "generate-text/openai-on-finish"
  static let description = "Shows how to inspect the finish event emitted by generateText(onFinish:)."

  static func run() async throws {
    do {
      let apiKey = try EnvLoader.require("OPENAI_API_KEY")
      Logger.debug("Using OPENAI_API_KEY prefix: \(apiKey.prefix(8))...")

      let result = try await generateText(
        model: openai("gpt-4o"),
        prompt: "Invent a new holiday and describe its traditions.",
        onFinish: { event in
          if let json = FinishEventLogger.encode(event: event) {
            Logger.section("onFinish Event")
            Logger.info(json)
          }
        }
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Total Usage")
      Helpers.printJSON(result.totalUsage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

private struct FinishEventLogger {
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

  struct StepLog: Encodable {
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

  struct FinishLog: Encodable {
    let finishReason: FinishReason
    let text: String
    let reasoningText: String?
    let reasoning: [ReasoningLog]
    let toolCalls: [ToolCallLog]
    let toolResults: [ToolResultLog]
    let usage: LanguageModelUsage
    let totalUsage: LanguageModelUsage
    let warnings: [CallWarning]?
    let providerMetadata: ProviderMetadata?
    let steps: [StepLog]
  }

  static func encode(event: GenerateTextFinishEvent) -> String? {
    let toolCalls = event.toolCalls.map(Self.makeToolCallLog(_:))
    let toolResults = event.toolResults.map(Self.makeToolResultLog(_:))
    let reasoning = event.reasoning.map(Self.makeReasoningLog(_:))
    let steps = event.steps.enumerated().map { index, step in
      makeStepLog(step, index: index + 1)
    }

    let payload = FinishLog(
      finishReason: event.finishReason,
      text: event.text,
      reasoningText: event.reasoningText,
      reasoning: reasoning,
      toolCalls: toolCalls,
      toolResults: toolResults,
      usage: event.usage,
      totalUsage: event.totalUsage,
      warnings: event.warnings,
      providerMetadata: event.providerMetadata,
      steps: steps
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
      let data = try encoder.encode(payload)
      return String(data: data, encoding: .utf8)
    } catch {
      Logger.warning("Failed to encode finish event: \(error)")
      return nil
    }
  }

  private static func makeToolCallLog(_ call: TypedToolCall) -> ToolCallLog {
    ToolCallLog(
      toolCallId: call.toolCallId,
      toolName: call.toolName,
      input: call.input,
      providerExecuted: call.providerExecuted,
      providerMetadata: call.providerMetadata,
      dynamic: call.isDynamic,
      invalid: call.invalid
    )
  }

  private static func makeToolResultLog(_ result: TypedToolResult) -> ToolResultLog {
    ToolResultLog(
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

  private static func makeReasoningLog(_ output: ReasoningOutput) -> ReasoningLog {
    ReasoningLog(text: output.text, providerMetadata: output.providerMetadata)
  }

  private static func makeStepLog(_ step: StepResult, index: Int) -> StepLog {
    StepLog(
      index: index,
      finishReason: step.finishReason,
      text: step.text,
      reasoning: step.reasoning.map(makeReasoningLog(_:)),
      toolCalls: step.toolCalls.map(makeToolCallLog(_:)),
      toolResults: step.toolResults.map(makeToolResultLog(_:)),
      usage: step.usage,
      warnings: step.warnings,
      providerMetadata: step.providerMetadata
    )
  }
}
