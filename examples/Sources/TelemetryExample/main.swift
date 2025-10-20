/**
 Telemetry Example

 Demonstrates OpenTelemetry integration in AI SDK.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/telemetry.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct TelemetryExample: CLIExample {
  static let name = "Telemetry"
  static let description = "OpenTelemetry integration for observability"

  static func run() async throws {
    // Example 1: Basic Telemetry
    Logger.section("Example 1: Basic Telemetry")
    Logger.info("Enabling telemetry for generateText...")

    let result1 = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Say hello in one sentence.",
      experimentalTelemetry: TelemetrySettings(isEnabled: true)
    )

    Logger.info("✅ Response: \(result1.text)")
    Logger.info("   Telemetry was collected (check OpenTelemetry backend)")

    // Example 2: Telemetry with Privacy
    Logger.section("Example 2: Telemetry with Privacy Controls")
    Logger.info("Disabling input/output recording for sensitive data...")

    _ = try await generateText(
      model: openai("gpt-4o"),
      prompt: "This is sensitive user data that should not be recorded.",
      experimentalTelemetry: TelemetrySettings(
        isEnabled: true,
        recordInputs: false,
        recordOutputs: false
      )
    )

    Logger.info("✅ Response received (not recorded in telemetry)")
    Logger.info("   Only metadata and usage stats were collected")

    // Example 3: Telemetry with Metadata
    Logger.section("Example 3: Telemetry with Function ID and Metadata")
    Logger.info("Adding custom metadata to telemetry...")

    let result3 = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Count from 1 to 3.",
      experimentalTelemetry: TelemetrySettings(
        isEnabled: true,
        functionId: "example-counter-function",
        metadata: [
          "user_id": "user-123",
          "session_id": "session-456",
          "environment": "development"
        ]
      )
    )

    Logger.info("✅ Response: \(result3.text)")
    Logger.info("   Function ID: example-counter-function")
    Logger.info("   Custom metadata included in telemetry")

    // Example 4: Streaming with Telemetry
    Logger.section("Example 4: Streaming with Telemetry")
    Logger.info("Enabling telemetry for streamText...")

    let result4 = try await streamText(
      model: openai("gpt-4o"),
      prompt: "Count to 5.",
      experimentalTelemetry: TelemetrySettings(
        isEnabled: true,
        functionId: "stream-counter"
      )
    )

    Logger.info("Streaming:")
    for try await textPart in result4.textStream {
      print(textPart, terminator: "")
      fflush(stdout)
    }
    print()
    Logger.info("✅ Stream complete with telemetry collected")
    Logger.info("   Metrics include: msToFirstChunk, msToFinish, avgTokensPerSecond")

    // Example 5: Telemetry Disabled
    Logger.section("Example 5: Telemetry Disabled (Default)")
    Logger.info("Making call without telemetry...")

    let result5 = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Say goodbye."
      // No experimentalTelemetry parameter = disabled by default
    )

    Logger.info("✅ Response: \(result5.text)")
    Logger.info("   No telemetry data collected")

    // Summary
    Logger.separator()
    Logger.info("Telemetry examples complete!")
    Logger.info("Key concepts:")
    Logger.info("  • Enable telemetry with TelemetrySettings(isEnabled: true)")
    Logger.info("  • Control privacy with recordInputs/recordOutputs")
    Logger.info("  • Add functionId for identifying specific functions")
    Logger.info("  • Include custom metadata for context")
    Logger.info("  • Works with generateText, streamText, and other AI functions")
    Logger.info("  • Integrates with OpenTelemetry for monitoring and tracing")
  }
}
