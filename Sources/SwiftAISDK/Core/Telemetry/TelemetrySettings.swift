/**
 Telemetry configuration.

 Port of `@ai-sdk/ai/src/telemetry/telemetry-settings.ts`.

 This is meant to be both flexible for custom app requirements (metadata)
 and extensible for standardization (example: functionId, more to come).
 */

/// Telemetry configuration
public struct TelemetrySettings: Sendable {
    /// Enable or disable telemetry. Disabled by default while experimental.
    public let isEnabled: Bool?

    /// Enable or disable input recording. Enabled by default.
    ///
    /// You might want to disable input recording to avoid recording sensitive
    /// information, to reduce data transfers, or to increase performance.
    public let recordInputs: Bool?

    /// Enable or disable output recording. Enabled by default.
    ///
    /// You might want to disable output recording to avoid recording sensitive
    /// information, to reduce data transfers, or to increase performance.
    public let recordOutputs: Bool?

    /// Identifier for this function. Used to group telemetry data by function.
    public let functionId: String?

    /// Additional information to include in the telemetry data.
    public let metadata: Attributes?

    /// A custom tracer to use for the telemetry data.
    public let tracer: (any Tracer)?

    public init(
        isEnabled: Bool? = nil,
        recordInputs: Bool? = nil,
        recordOutputs: Bool? = nil,
        functionId: String? = nil,
        metadata: Attributes? = nil,
        tracer: (any Tracer)? = nil
    ) {
        self.isEnabled = isEnabled
        self.recordInputs = recordInputs
        self.recordOutputs = recordOutputs
        self.functionId = functionId
        self.metadata = metadata
        self.tracer = tracer
    }
}
