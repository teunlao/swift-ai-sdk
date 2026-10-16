import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Validates a tool context against the tool's optional context schema.

 Port of `@ai-sdk/ai/src/generate-text/validate-tool-context.ts`. Without a
 schema the context is returned as is.

 - Throws: `TypeValidationError` when the context does not match the schema.
 */
func validateToolContext(
    toolName: String,
    context: Context?,
    contextSchema: FlexibleSchema<JSONValue>?
) async throws -> Context? {
    guard let contextSchema else { return context }

    let raw: Any = context.map { jsonValueToFoundation(.object($0)) } ?? NSNull()
    let validated = try await validateTypes(
        ValidateTypesOptions(
            value: raw,
            schema: contextSchema,
            context: TypeValidationContext(field: "tool context", entityName: toolName)
        )
    )
    if case .object(let object) = validated { return object }
    return nil
}

/**
 Validates the tool call concurrency setting.

 Port of `prepareToolCallConcurrency` from `@ai-sdk/ai/src/generate-text/tool-call-concurrency.ts`.
 */
func prepareToolCallConcurrency(_ toolCallConcurrency: Int?) throws -> Int? {
    guard let toolCallConcurrency else { return nil }
    if toolCallConcurrency < 1 {
        throw InvalidArgumentError(
            parameter: "toolCallConcurrency",
            value: .number(Double(toolCallConcurrency)),
            message: "toolCallConcurrency must be >= 1"
        )
    }
    return toolCallConcurrency
}

/**
 Runs `execute` for every item with at most `concurrency` running at once and
 returns the results in item order.

 Port of `mapWithConcurrency` from `@ai-sdk/ai/src/generate-text/tool-call-concurrency.ts`:
 workers take items in order, and a failure stops further items from starting.
 */
func mapWithConcurrency<Input: Sendable, Output: Sendable>(
    _ items: [Input],
    concurrency: Int?,
    abortSignal: (@Sendable () -> Bool)?,
    execute: @escaping @Sendable (Input, Int) async throws -> Output
) async throws -> [Output] {
    let limit = min(concurrency ?? items.count, items.count)
    guard limit > 0 else { return [] }

    return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
        var results = [Output?](repeating: nil, count: items.count)
        var nextIndex = 0

        func startNext() throws {
            if abortSignal?() == true {
                throw CancellationError()
            }
            let index = nextIndex
            let item = items[index]
            nextIndex += 1
            group.addTask { (index, try await execute(item, index)) }
        }

        while nextIndex < limit {
            try startNext()
        }

        while let (index, output) = try await group.next() {
            results[index] = output
            if nextIndex < items.count {
                try startNext()
            }
        }

        return results.map { $0! }
    }
}

/// An abort signal that fires once `milliseconds` have elapsed.
func deadlineAbortSignal(_ milliseconds: Int?) -> (@Sendable () -> Bool)? {
    guard let milliseconds else { return nil }
    let deadline = now() + Double(milliseconds)
    return { now() >= deadline }
}

/// Output of a tool execution with its duration.
struct ExecutedToolOutput: Sendable {
    let output: ToolOutput
    let toolExecutionMs: Double
}

/**
 Executes a single tool call and reports its lifecycle.

 Port of `@ai-sdk/ai/src/generate-text/execute-tool-call.ts`:
 1. validates the tool context,
 2. notifies `onToolExecutionStart`,
 3. runs `execute` inside the telemetry tool context with the tool timeout,
    forwarding preliminary outputs,
 4. notifies `onToolExecutionEnd` with the result or error.

 Returns `nil` when the tool has no execute function.
 */
func executeToolCall(
    toolCall: TypedToolCall,
    tools: ToolSet?,
    toolsContext: ToolsContext,
    callId: String,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    timeout: TimeoutConfiguration?,
    telemetry: TelemetryDispatcher,
    onToolExecutionStart: OnToolExecutionStartCallback?,
    onToolExecutionEnd: OnToolExecutionEndCallback?,
    onPreliminaryToolResult: (@Sendable (TypedToolResult) async -> Void)? = nil
) async throws -> ExecutedToolOutput? {
    let toolName = toolCall.toolName
    let toolCallId = toolCall.toolCallId
    let input = toolCall.input

    guard let tool = tools?[toolName], let execute = tool.execute else {
        return nil
    }

    let context = try await validateToolContext(
        toolName: toolName,
        context: toolsContext[toolName],
        contextSchema: tool.contextSchema
    )

    let startEvent = ToolExecutionStartEvent(
        callId: callId,
        messages: messages,
        toolCall: toolCall,
        toolContext: context
    )

    await notify(
        invoke(onToolExecutionStart, with: startEvent),
        { await telemetry.onToolExecutionStart(startEvent) }
    )

    let toolAbortSignal = mergeAbortSignals(
        abortSignal,
        deadlineAbortSignal(getToolTimeoutMs(timeout, toolName: toolName))
    )
    let isDynamic = tool.type == .dynamic
    let timing = ToolExecutionTiming()

    let toolOutput: ToolOutput
    do {
        let output: JSONValue = try await telemetry.executeTool(startEvent) {
            let startTime = now()
            defer { timing.record(now() - startTime) }

            var finalOutput: JSONValue = .null
            let stream = executeTool(
                execute: execute,
                input: input,
                options: ToolExecutionOptions(
                    toolCallId: toolCallId,
                    messages: messages,
                    abortSignal: toolAbortSignal,
                    context: context
                )
            )

            for try await part in stream {
                switch part {
                case .preliminary(let output):
                    await onPreliminaryToolResult?(makeToolResult(
                        toolCall: toolCall,
                        output: output,
                        dynamic: isDynamic,
                        preliminary: true
                    ))
                case .final(let output):
                    finalOutput = output ?? .null
                }
            }
            return finalOutput
        }

        toolOutput = .result(makeToolResult(toolCall: toolCall, output: output, dynamic: isDynamic, preliminary: nil))
    } catch {
        toolOutput = .error(makeToolError(toolCall: toolCall, error: error, dynamic: isDynamic))
    }

    let endEvent = ToolExecutionEndEvent(
        callId: callId,
        messages: messages,
        toolCall: toolCall,
        toolContext: context,
        toolOutput: toolOutput,
        toolExecutionMs: timing.value
    )

    await notify(
        invoke(onToolExecutionEnd, with: endEvent),
        { await telemetry.onToolExecutionEnd(endEvent) }
    )

    return ExecutedToolOutput(output: toolOutput, toolExecutionMs: timing.value)
}

/**
 Executes tool calls with optional concurrency and returns the outputs in call order.

 Port of the `executeTools` helper of `@ai-sdk/ai/src/generate-text/generate-text.ts`.
 */
func executeToolCalls(
    _ toolCalls: [TypedToolCall],
    tools: ToolSet?,
    toolsContext: ToolsContext,
    callId: String,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    timeout: TimeoutConfiguration?,
    telemetry: TelemetryDispatcher,
    toolCallConcurrency: Int?,
    onToolExecutionStart: OnToolExecutionStartCallback?,
    onToolExecutionEnd: OnToolExecutionEndCallback?
) async throws -> [ExecutedToolOutput] {
    let outputs = try await mapWithConcurrency(
        toolCalls,
        concurrency: toolCallConcurrency,
        abortSignal: abortSignal
    ) { toolCall, _ in
        try await executeToolCall(
            toolCall: toolCall,
            tools: tools,
            toolsContext: toolsContext,
            callId: callId,
            messages: messages,
            abortSignal: abortSignal,
            timeout: timeout,
            telemetry: telemetry,
            onToolExecutionStart: onToolExecutionStart,
            onToolExecutionEnd: onToolExecutionEnd
        )
    }
    return outputs.compactMap { $0 }
}

private final class ToolExecutionTiming: @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: Double = 0

    func record(_ value: Double) {
        lock.lock()
        milliseconds = value
        lock.unlock()
    }

    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return milliseconds
    }
}

func makeToolResult(
    toolCall: TypedToolCall,
    output: JSONValue,
    dynamic: Bool,
    preliminary: Bool?
) -> TypedToolResult {
    if dynamic {
        return .dynamic(DynamicToolResult(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            output: output,
            preliminary: preliminary,
            providerMetadata: toolCall.providerMetadata,
            toolMetadata: toolCall.toolMetadata
        ))
    }
    return .static(StaticToolResult(
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: toolCall.input,
        output: output,
        preliminary: preliminary,
        providerMetadata: toolCall.providerMetadata,
        toolMetadata: toolCall.toolMetadata
    ))
}

func makeToolError(
    toolCall: TypedToolCall,
    error: any Error,
    dynamic: Bool
) -> TypedToolError {
    if dynamic {
        return .dynamic(DynamicToolError(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            error: error,
            providerMetadata: toolCall.providerMetadata,
            toolMetadata: toolCall.toolMetadata
        ))
    }
    return .static(StaticToolError(
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: toolCall.input,
        error: error,
        providerMetadata: toolCall.providerMetadata,
        toolMetadata: toolCall.toolMetadata
    ))
}
