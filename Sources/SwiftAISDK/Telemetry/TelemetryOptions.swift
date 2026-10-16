import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Telemetry configuration of a call.

 Port of `@ai-sdk/ai/src/telemetry/telemetry-options.ts`.
 */
public struct TelemetryOptions: Sendable {
    /// Enable or disable telemetry. Enabled when an integration is available; set `false` to opt out.
    public var isEnabled: Bool?

    /// Enable or disable input recording. Enabled by default.
    public var recordInputs: Bool?

    /// Enable or disable output recording. Enabled by default.
    public var recordOutputs: Bool?

    /// Identifier for this function, used to group telemetry data.
    public var functionId: String?

    /// Top-level runtime context keys included in telemetry. Keys are excluded unless set to `true`.
    public var includeRuntimeContext: [String: Bool]?

    /// Top-level tool context keys included in telemetry, per tool name.
    /// Keys are excluded unless set to `true`.
    public var includeToolsContext: [String: [String: Bool]]?

    /// Integrations for this call. When set, they replace the globally registered integrations.
    public var integrations: [any Telemetry]?

    public init(
        isEnabled: Bool? = nil,
        recordInputs: Bool? = nil,
        recordOutputs: Bool? = nil,
        functionId: String? = nil,
        includeRuntimeContext: [String: Bool]? = nil,
        includeToolsContext: [String: [String: Bool]]? = nil,
        integrations: [any Telemetry]? = nil
    ) {
        self.isEnabled = isEnabled
        self.recordInputs = recordInputs
        self.recordOutputs = recordOutputs
        self.functionId = functionId
        self.includeRuntimeContext = includeRuntimeContext
        self.includeToolsContext = includeToolsContext
        self.integrations = integrations
    }
}

private final class TelemetryRegistry: @unchecked Sendable {
    static let shared = TelemetryRegistry()

    private let lock = NSLock()
    private var integrations: [any Telemetry] = []

    func register(_ newIntegrations: [any Telemetry]) {
        lock.lock()
        defer { lock.unlock() }
        integrations.append(contentsOf: newIntegrations)
    }

    func all() -> [any Telemetry] {
        lock.lock()
        defer { lock.unlock() }
        return integrations
    }
}

/**
 Registers telemetry integrations globally.

 Port of `registerTelemetry` from `@ai-sdk/ai/src/telemetry/telemetry-registry.ts`.
 */
public func registerTelemetry(_ integrations: any Telemetry...) {
    TelemetryRegistry.shared.register(integrations)
}

/// The globally registered telemetry integrations.
func getGlobalTelemetryIntegrations() -> [any Telemetry] {
    TelemetryRegistry.shared.all()
}

/**
 Returns the context with only the top-level keys marked for inclusion.

 Port of `filterIncludedContext` from `@ai-sdk/ai/src/telemetry/filter-included-context.ts`.
 */
func filterIncludedContext(_ context: Context?, include: [String: Bool]?) -> Context {
    guard let context else { return [:] }
    return context.filter { include?[$0.key] == true }
}

/// Port of `filterToolsContext` from `@ai-sdk/ai/src/telemetry/filter-included-context.ts`.
func filterToolsContext(_ toolsContext: ToolsContext, include: [String: [String: Bool]]?) -> ToolsContext {
    guard let include else { return [:] }
    return Dictionary(uniqueKeysWithValues: toolsContext.map { toolName, context in
        (toolName, filterIncludedContext(context, include: include[toolName]))
    })
}

/// Port of `filterToolContext` from `@ai-sdk/ai/src/telemetry/filter-included-context.ts`.
func filterToolContext(toolName: String, _ toolContext: Context?, include: [String: [String: Bool]]?) -> Context {
    filterIncludedContext(toolContext, include: include?[toolName])
}
