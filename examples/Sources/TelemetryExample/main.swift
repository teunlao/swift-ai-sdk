/**
 Telemetry Example

 Demonstrates telemetry integrations in AI SDK.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/telemetry.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

struct ConsoleTracer: Tracer {
  func startSpan(name: String, options: SpanOptions?) -> any Span {
    Logger.info("   start \(name), parent: \(options?.parent?.spanContext().spanId ?? "root")")
    let span = ConsoleSpan(name: name, parent: options?.parent?.spanContext())
    span.setAttributes(options?.attributes ?? [:])
    return span
  }

  func startActiveSpan<T>(_ name: String, options: SpanOptions?, _ fn: @Sendable (any Span) async throws -> T) async rethrows -> T {
    let span = startSpan(name: name, options: options)
    defer { span.end() }
    return try await fn(span)
  }
}

final class ConsoleSpan: Span, Sendable {
  let name: String
  private let context: SpanContext
  init(name: String, parent: SpanContext?) {
    self.name = name
    self.context = SpanContext(traceId: parent?.traceId ?? UUID().uuidString, spanId: UUID().uuidString, traceFlags: 1)
  }
  func spanContext() -> SpanContext { context }
  @discardableResult func setAttribute(_ key: String, value: AttributeValue) -> Self {
    Logger.info("   \(name): \(key) = \(value)")
    return self
  }
  @discardableResult func setAttributes(_ attributes: Attributes) -> Self {
    for (key, value) in attributes { setAttribute(key, value: value) }
    return self
  }
  func addEvent(_ name: String, attributes: Attributes?) -> Self { self }
  func setStatus(_ status: SpanStatus) -> Self { self }
  func updateName(_ name: String) -> Self { self }
  func isRecording() -> Bool { true }
  func recordException(_ exception: ExceptionEvent) -> Self {
    Logger.info("   error: \(exception.message ?? "unknown")")
    return self
  }
  func end() { Logger.info("   end \(name)") }
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
      telemetry: TelemetryOptions(functionId: "greeting", integrations: [OpenTelemetry(tracer: ConsoleTracer())])
    )
    Logger.info("✅ Response: \(result1.text)")

    Logger.section("Example 2: Privacy controls")
    _ = try await generateText(
      model: openai("gpt-4o"),
      prompt: "This is sensitive user data that should not be recorded.",
      telemetry: TelemetryOptions(recordInputs: false, recordOutputs: false, integrations: [OpenTelemetry(tracer: ConsoleTracer())])
    )
    Logger.info("✅ Integrations were told not to record inputs or outputs")

    Logger.section("Example 3: Streaming")
    let result3 = try streamText(
      model: openai("gpt-4o"),
      prompt: "Count to 5.",
      telemetry: TelemetryOptions(functionId: "stream-counter", integrations: [OpenTelemetry(tracer: ConsoleTracer())])
    )
    for try await textPart in result3.textStream {
      print(textPart, terminator: "")
      fflush(stdout)
    }
    print()

    Logger.section("Example 4: Global registration and opting out")
    registerTelemetry(OpenTelemetry(tracer: ConsoleTracer()))
    _ = try await generateText(model: openai("gpt-4o"), prompt: "Say goodbye.")
    _ = try await generateText(
      model: openai("gpt-4o"),
      prompt: "Say goodbye quietly.",
      telemetry: TelemetryOptions(isEnabled: false)
    )
    Logger.info("✅ The second call reported no events")
  }
}
