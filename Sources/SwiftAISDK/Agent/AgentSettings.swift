import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Configuration options for an `Agent` instance.
 
 Port of `@ai-sdk/ai/src/agent/agent-settings.ts`.
 
 The settings mirror the JavaScript structure and encapsulate both the
 base call settings (sampling parameters, headers, etc.) and the
 higher-level agent behaviour such as tool selection and callbacks.
 */
public struct AgentSettings<OutputValue: Sendable, PartialOutputValue: Sendable>: Sendable {
    // MARK: - Core identification

    /// Optional agent name used for logging/telemetry.
    public var name: String?

    /// Default system instruction applied when a prompt does not override it.
    public var system: String?

    /// Language model to be used for generation/streaming.
    public var model: LanguageModel

    /// Tool set available to the agent. Tools must be supported by the model.
    public var tools: ToolSet?

    /// Tool choice directive. Defaults to `.auto` when not specified.
    public var toolChoice: ToolChoice?

    /// Optional stop conditions evaluated after each step. When `nil`, the agent
    /// defaults to `stepCountIs(20)` (see Agent implementation).
    public var stopWhen: [StopCondition]?

    // MARK: - Behaviour modifiers

    /// Experimental telemetry configuration forwarded to generation helpers.
    public var experimentalTelemetry: TelemetrySettings?

    /// Whitelist of tool identifiers that may be invoked by the model.
    public var activeTools: [String]?

    /// Structured output specification (experimental).
    public var experimentalOutput: Output.Specification<OutputValue, PartialOutputValue>?

    /// Deprecated hook for transforming per-step settings (kept for parity).
    public var experimentalPrepareStep: PrepareStepFunction?

    /// Preferred hook for transforming per-step settings.
    public var prepareStep: PrepareStepFunction?

    /// Tool-call repair callback used when parsing fails (experimental).
    public var experimentalRepairToolCall: ToolCallRepairFunction?

    /// Callback invoked after each completed step (intermediate result).
    public var onStepFinish: GenerateTextOnStepFinishCallback?

    /// Callback invoked after all steps are finished.
    public var onFinish: GenerateTextOnFinishCallback?

    /// Provider-specific options forwarded to the underlying model implementation.
    public var providerOptions: ProviderOptions?

    /// Experimental context passed into tool executions.
    public var experimentalContext: JSONValue?

    /// Call-level configuration (sampling, headers, retries, …).
    public var callSettings: CallSettings

    // MARK: - Initialiser

    public init(
        name: String? = nil,
        system: String? = nil,
        model: LanguageModel,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        stopWhen: [StopCondition]? = nil,
        experimentalTelemetry: TelemetrySettings? = nil,
        activeTools: [String]? = nil,
        experimentalOutput: Output.Specification<OutputValue, PartialOutputValue>? = nil,
        experimentalPrepareStep: PrepareStepFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        experimentalRepairToolCall: ToolCallRepairFunction? = nil,
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        providerOptions: ProviderOptions? = nil,
        experimentalContext: JSONValue? = nil,
        callSettings: CallSettings = CallSettings()
    ) {
        self.name = name
        self.system = system
        self.model = model
        self.tools = tools
        self.toolChoice = toolChoice
        self.stopWhen = stopWhen
        self.experimentalTelemetry = experimentalTelemetry
        self.activeTools = activeTools
        self.experimentalOutput = experimentalOutput
        self.experimentalPrepareStep = experimentalPrepareStep
        self.prepareStep = prepareStep
        self.experimentalRepairToolCall = experimentalRepairToolCall
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.providerOptions = providerOptions
        self.experimentalContext = experimentalContext
        self.callSettings = callSettings
    }
}

/// Convenience alias for the most common agent configuration (no structured outputs).
public typealias BasicAgentSettings = AgentSettings<Never, Never>

// MARK: - Backwards compatibility aliases

@available(*, deprecated, renamed: "AgentSettings")
public typealias Experimental_AgentSettings<OutputValue: Sendable, PartialOutputValue: Sendable> = AgentSettings<OutputValue, PartialOutputValue>
