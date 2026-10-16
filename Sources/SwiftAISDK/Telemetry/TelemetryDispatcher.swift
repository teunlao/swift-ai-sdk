import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Fans lifecycle events out to the telemetry integrations of a call.

 Port of `createTelemetryDispatcher` from
 `@ai-sdk/ai/src/telemetry/create-telemetry-dispatcher.ts` combined with the
 context restriction of
 `@ai-sdk/ai/src/generate-text/restricted-telemetry-dispatcher.ts`: runtime and
 tool contexts reach integrations only for the keys `includeRuntimeContext` /
 `includeToolsContext` mark. Per-call integrations replace the global ones;
 `isEnabled: false` disables every integration. Integration errors are ignored.
 Node's tracing channel publishing has no Swift counterpart and is not ported.
 */
struct TelemetryDispatcher: Sendable {
    let integrations: [any Telemetry]
    private let options: TelemetryOptions?

    init(telemetry: TelemetryOptions?) {
        self.options = telemetry
        if telemetry?.isEnabled == false {
            self.integrations = []
        } else {
            self.integrations = telemetry?.integrations ?? getGlobalTelemetryIntegrations()
        }
    }

    var isActive: Bool { !integrations.isEmpty }

    private func wrap<Event: Sendable>(_ event: Event) -> TelemetryEvent<Event> {
        TelemetryEvent(
            event: event,
            recordInputs: options?.recordInputs,
            recordOutputs: options?.recordOutputs,
            functionId: options?.functionId
        )
    }

    private func fanOut(_ deliver: @escaping @Sendable (any Telemetry) async throws -> Void) async {
        let integrations = self.integrations
        guard !integrations.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for integration in integrations {
                group.addTask { try? await deliver(integration) }
            }
        }
    }

    // MARK: - Context restriction

    private func restrict(_ context: Context) -> Context {
        filterIncludedContext(context, include: options?.includeRuntimeContext)
    }

    private func restrict(_ toolsContext: ToolsContext) -> ToolsContext {
        filterToolsContext(toolsContext, include: options?.includeToolsContext)
    }

    private func restrict(_ step: any StepResult) -> any StepResult {
        DefaultStepResult(
            callId: step.callId,
            stepNumber: step.stepNumber,
            model: step.model,
            toolsContext: restrict(step.toolsContext),
            runtimeContext: restrict(step.runtimeContext),
            content: step.content,
            finishReason: step.finishReason,
            rawFinishReason: step.rawFinishReason,
            usage: step.usage,
            performance: step.performance,
            warnings: step.warnings,
            request: step.request,
            response: step.response,
            providerMetadata: step.providerMetadata
        )
    }

    // MARK: - Lifecycle events

    func onStart(_ event: TelemetryStartEvent) async {
        guard isActive else { return }
        let restricted: TelemetryStartEvent
        switch event {
        case .generateText(let start):
            restricted = .generateText(start.with(
                runtimeContext: restrict(start.runtimeContext),
                toolsContext: restrict(start.toolsContext)
            ))
        case .generateObject:
            restricted = event
        }
        let wrapped = wrap(restricted)
        await fanOut { try await $0.onStart(wrapped) }
    }

    func onStepStart(_ event: GenerateTextStepStartEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event.with(
            runtimeContext: restrict(event.runtimeContext),
            toolsContext: restrict(event.toolsContext),
            steps: event.steps.map(restrict)
        ))
        await fanOut { try await $0.onStepStart(wrapped) }
    }

    func onLanguageModelCallStart(_ event: LanguageModelCallStartEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event)
        await fanOut { try await $0.onLanguageModelCallStart(wrapped) }
    }

    func onLanguageModelCallEnd(_ event: LanguageModelCallEndEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event)
        await fanOut { try await $0.onLanguageModelCallEnd(wrapped) }
    }

    func onToolExecutionStart(_ event: ToolExecutionStartEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event.with(toolContext: restrictToolContext(event.toolCall.toolName, event.toolContext)))
        await fanOut { try await $0.onToolExecutionStart(wrapped) }
    }

    func onToolExecutionEnd(_ event: ToolExecutionEndEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event.with(toolContext: restrictToolContext(event.toolCall.toolName, event.toolContext)))
        await fanOut { try await $0.onToolExecutionEnd(wrapped) }
    }

    func onStepEnd(_ event: any StepResult) async {
        guard isActive else { return }
        let wrapped = wrap(restrict(event))
        await fanOut { try await $0.onStepEnd(wrapped) }
    }

    func onObjectStepStart(_ event: GenerateObjectStepStartEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event)
        await fanOut { try await $0.onObjectStepStart(wrapped) }
    }

    func onObjectStepEnd(_ event: GenerateObjectStepEndEvent) async {
        guard isActive else { return }
        let wrapped = wrap(event)
        await fanOut { try await $0.onObjectStepEnd(wrapped) }
    }

    func onEnd(_ event: TelemetryEndEvent) async {
        guard isActive else { return }
        let restricted: TelemetryEndEvent
        switch event {
        case .generateText(let end):
            restricted = .generateText(end.with(
                runtimeContext: restrict(end.runtimeContext),
                toolsContext: restrict(end.toolsContext),
                steps: end.steps.map(restrict)
            ))
        case .generateObject:
            restricted = event
        }
        let wrapped = wrap(restricted)
        await fanOut { try await $0.onEnd(wrapped) }
    }

    func onAbort(_ event: GenerateTextAbortEvent) async {
        guard isActive else { return }
        let wrapped = wrap(GenerateTextAbortEvent(
            callId: event.callId,
            steps: event.steps.map(restrict),
            reason: event.reason
        ))
        await fanOut { try await $0.onAbort(wrapped) }
    }

    func onError(callId: String, error: any Error) async {
        guard isActive else { return }
        let wrapped = wrap(TelemetryErrorEvent(callId: callId, error: error))
        await fanOut { try await $0.onError(wrapped) }
    }

    private func restrictToolContext(_ toolName: String, _ context: Context?) -> Context? {
        filterToolContext(toolName: toolName, context, include: options?.includeToolsContext)
    }

    // MARK: - Execution context

    /// Runs a provider call inside every integration's model-call context; the last integration is outermost.
    func executeLanguageModelCall<T: Sendable>(
        _ event: LanguageModelCallStartEvent,
        execute: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let wrapped = wrap(event)
        var run = execute
        for integration in integrations {
            let inner = run
            run = { try await integration.executeLanguageModelCall(wrapped, execute: inner) }
        }
        return try await run()
    }

    /// Runs a tool execution inside every integration's tool context; the last integration is outermost.
    func executeTool<T: Sendable>(
        _ event: ToolExecutionStartEvent,
        execute: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let wrapped = wrap(event)
        var run = execute
        for integration in integrations {
            let inner = run
            run = { try await integration.executeTool(wrapped, execute: inner) }
        }
        return try await run()
    }
}

/// A callback bound to an event, for `notify`.
func invoke<Event: Sendable>(
    _ callback: (@Sendable (Event) async throws -> Void)?,
    with event: Event
) -> (@Sendable () async throws -> Void)? {
    guard let callback else { return nil }
    return { try await callback(event) }
}

/**
 Notifies callbacks of an event in parallel. Errors thrown by callbacks are
 ignored and never interrupt the operation.

 Port of `@ai-sdk/ai/src/util/notify.ts`.
 */
func notify(_ callbacks: (@Sendable () async throws -> Void)?...) async {
    let callbacks = callbacks.compactMap { $0 }
    guard !callbacks.isEmpty else { return }
    await withTaskGroup(of: Void.self) { group in
        for callback in callbacks {
            group.addTask { try? await callback() }
        }
    }
}
