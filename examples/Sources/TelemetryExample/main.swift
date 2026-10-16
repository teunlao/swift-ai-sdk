/**
 Telemetry Example

 Demonstrates telemetry integrations in AI SDK.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/telemetry.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

/// Prints each lifecycle event an operation goes through.
struct ConsoleTelemetry: Telemetry {
  func onStart(_ event: TelemetryEvent<TelemetryStartEvent>) async throws {
    Logger.info("   start \(event.event.operationId) (function: \(event.functionId ?? "-"))")
  }

  func onStepEnd(_ event: TelemetryEvent<any StepResult>) async throws {
    Logger.info("   step \(event.event.stepNumber) finished: \(event.event.finishReason.rawValue)")
  }

  func onEnd(_ event: TelemetryEvent<TelemetryEndEvent>) async throws {
    Logger.info("   end \(event.event.callId)")
  }
}

@main
struct TelemetryExample: CLIExample {
  static let name = "Telemetry"
  static let description = "Telemetry integrations for observability"

  static func run() async throws {
    Logger.section("Example 1: Per-call integration")
    let result1 = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Say hello in one sentence.",
      telemetry: TelemetryOptions(functionId: "greeting", integrations: [ConsoleTelemetry()])
    )
    Logger.info("✅ Response: \(result1.text)")

    Logger.section("Example 2: Privacy controls")
    _ = try await generateText(
      model: openai("gpt-4o"),
      prompt: "This is sensitive user data that should not be recorded.",
      telemetry: TelemetryOptions(recordInputs: false, recordOutputs: false, integrations: [ConsoleTelemetry()])
    )
    Logger.info("✅ Integrations were told not to record inputs or outputs")

    Logger.section("Example 3: Streaming")
    let result3 = try streamText(
      model: openai("gpt-4o"),
      prompt: "Count to 5.",
      telemetry: TelemetryOptions(functionId: "stream-counter", integrations: [ConsoleTelemetry()])
    )
    for try await textPart in result3.textStream {
      print(textPart, terminator: "")
      fflush(stdout)
    }
    print()

    Logger.section("Example 4: Global registration and opting out")
    registerTelemetry(ConsoleTelemetry())
    _ = try await generateText(model: openai("gpt-4o"), prompt: "Say goodbye.")
    _ = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Say goodbye quietly.",
      telemetry: TelemetryOptions(isEnabled: false)
    )
    Logger.info("✅ The second call reported no events")
  }
}
