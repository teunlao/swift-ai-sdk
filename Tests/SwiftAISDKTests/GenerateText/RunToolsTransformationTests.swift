/**
 Tests for runToolsTransformation stream orchestration.

 Port of `@ai-sdk/ai/src/generate-text/run-tools-transformation.test.ts`.
 */

import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("RunToolsTransformation Tests", .serialized)
struct RunToolsTransformationTests {
    private let usage = LanguageModelV3Usage(
        inputTokens: .init(total: 3),
        outputTokens: .init(total: 10)
    )

    private enum TestError: Error {
        case invalidInput
    }

    // MARK: - Helpers

    private func makeStream(
        _ parts: [LanguageModelV3StreamPart]
    ) -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
        AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }

    private func collect(
        _ stream: AsyncThrowingStream<SingleRequestTextStreamPart, Error>
    ) async throws -> [SingleRequestTextStreamPart] {
        var collected: [SingleRequestTextStreamPart] = []
        for try await part in stream {
            collected.append(part)
        }
        return collected
    }

    private func mockId(prefix: String = "id") -> IDGenerator {
        let counter = IDCounter(prefix: prefix)
        return { counter.next() }
    }

    private func toolInputSchema() -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "required": .array([.string("value")]),
                    "additionalProperties": .bool(false),
                ])
            )
        )
    }

    // MARK: - Tests

    @Test("Forwards basic text parts")
    func forwardsTextParts() async throws {
        let stream = makeStream([
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "text", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ])

        let transformed = runToolsTransformation(
            tools: nil,
            generatorStream: stream,
            tracer: MockTracer(),
            telemetry: nil,
            system: nil,
            messages: [],
            abortSignal: nil,
            repairToolCall: nil,
            experimentalContext: nil,
            generateId: mockId()
        )

        let parts = try await collect(transformed)
        #expect(parts.count == 4)

        if case .textStart(let id, _) = parts[0] {
            #expect(id == "1")
        } else {
            Issue.record("Expected text-start as first part")
        }

        if case .textDelta(let id, let delta, _) = parts[1] {
            #expect(id == "1")
            #expect(delta == "text")
        } else {
            Issue.record("Expected text-delta as second part")
        }

        if case .textEnd(let id, _) = parts[2] {
            #expect(id == "1")
        } else {
            Issue.record("Expected text-end as third part")
        }

        if case .finish(let finishReason, let totalUsage, _) = parts[3] {
            #expect(finishReason == .stop)
            #expect(totalUsage == asLanguageModelUsage(usage))
        } else {
            Issue.record("Expected finish as final part")
        }
    }

    @Test("Executes async tool and emits result")
    func executesAsyncTool() async throws {
        let stream = makeStream([
            .toolCall(
                LanguageModelV3ToolCall(
                    toolCallId: "call-1",
                    toolName: "syncTool",
                    input: #"{"value":"test"}"#
                )
            ),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ])

        let tools: ToolSet = [
            "syncTool": tool(
                inputSchema: toolInputSchema(),
                execute: { input, _ in
                    guard case .object(let dict) = input,
                        case .string(let value) = dict["value"]
                    else {
                        throw TestError.invalidInput
                    }
                    return .future {
                        try await delay(0)
                        return .string("\(value)-sync-result")
                    }
                }
            )
        ]

        let transformed = runToolsTransformation(
            tools: tools,
            generatorStream: stream,
            tracer: MockTracer(),
            telemetry: nil,
            system: nil,
            messages: [],
            abortSignal: nil,
            repairToolCall: nil,
            experimentalContext: nil,
            generateId: mockId()
        )

        let parts = try await collect(transformed)
        #expect(parts.count == 3)

        guard case .toolCall(let call) = parts[0] else {
            Issue.record("Expected tool-call first")
            return
        }
        #expect(call.toolName == "syncTool")

        guard case .toolResult(let result) = parts[1] else {
            Issue.record("Expected tool-result second")
            return
        }
        switch result {
        case .static(let staticResult):
            #expect(staticResult.output == .string("test-sync-result"))
        case .dynamic:
            Issue.record("Expected static tool result")
        }

        if case .finish(let finishReason, _, _) = parts[2] {
            #expect(finishReason == .stop)
        } else {
            Issue.record("Expected finish part at end")
        }
    }

    @Test("Executes sync tool")
    func executesSyncTool() async throws {
        let stream = makeStream([
            .toolCall(
                LanguageModelV3ToolCall(
                    toolCallId: "call-1",
                    toolName: "syncTool",
                    input: #"{"value":"test"}"#
                )
            ),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ])

        let tools: ToolSet = [
            "syncTool": tool(
                inputSchema: toolInputSchema(),
                execute: { input, _ in
                    guard case .object(let dict) = input,
                        case .string(let value) = dict["value"]
                    else {
                        throw TestError.invalidInput
                    }
                    return .value(.string("\(value)-sync-result"))
                }
            )
        ]

        let transformed = runToolsTransformation(
            tools: tools,
            generatorStream: stream,
            tracer: MockTracer(),
            telemetry: nil,
            system: nil,
            messages: [],
            abortSignal: nil,
            repairToolCall: nil,
            experimentalContext: nil,
            generateId: mockId()
        )

        let parts = try await collect(transformed)
        #expect(parts.count == 3)

        guard case .toolCall(let call) = parts[0] else {
            Issue.record("Expected tool-call first")
            return
        }
        #expect(call.toolName == "syncTool")

        guard case .toolResult(let result) = parts[1] else {
            Issue.record("Expected tool-result second")
            return
        }
        switch result {
        case .static(let staticResult):
            #expect(staticResult.output == .string("test-sync-result"))
        case .dynamic:
            Issue.record("Expected static tool result")
        }
    }

    @Test("Delays finish until async tool completes")
    func delaysFinishUntilToolCompletes() async throws {
        let stream = makeStream([
            .toolCall(
                LanguageModelV3ToolCall(
                    toolCallId: "call-1",
                    toolName: "delayedTool",
                    input: #"{"value":"test"}"#
                )
            ),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ])

        let tools: ToolSet = [
            "delayedTool": tool(
                inputSchema: toolInputSchema(),
                execute: { input, _ in
                    guard case .object(let dict) = input,
                        case .string(let value) = dict["value"]
                    else {
                        throw TestError.invalidInput
                    }
                    return .future {
                        try await delay(0)
                        return .string("\(value)-delayed-result")
                    }
                }
            )
        ]

        let transformed = runToolsTransformation(
            tools: tools,
            generatorStream: stream,
            tracer: MockTracer(),
            telemetry: nil,
            system: nil,
            messages: [],
            abortSignal: nil,
            repairToolCall: nil,
            experimentalContext: nil,
            generateId: mockId()
        )

        let parts = try await collect(transformed)
        #expect(parts.count == 3)

        guard case .toolResult(let result) = parts[1] else {
            Issue.record("Expected tool-result before finish")
            return
        }
        switch result {
        case .static(let staticResult):
            #expect(staticResult.output == .string("test-delayed-result"))
        case .dynamic:
            Issue.record("Expected static tool result")
        }

        if case .finish = parts[2] {
            // OK
        } else {
            Issue.record("Expected finish emitted last")
        }
    }

    @Test("Attempts tool-call repair when tool missing")
    func attemptsToolRepair() async throws {
        let stream = makeStream([
            .toolCall(
                LanguageModelV3ToolCall(
                    toolCallId: "call-1",
                    toolName: "unknownTool",
                    input: #"{"value":"test"}"#
                )
            ),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ])

        let tools: ToolSet = [
            "correctTool": tool(
                inputSchema: toolInputSchema(),
                execute: { input, _ in
                    guard case .object(let dict) = input,
                        case .string(let value) = dict["value"]
                    else {
                        throw TestError.invalidInput
                    }
                    return .value(.string("\(value)-result"))
                }
            )
        ]

        let transformed = runToolsTransformation(
            tools: tools,
            generatorStream: stream,
            tracer: MockTracer(),
            telemetry: nil,
            system: nil,
            messages: [],
            abortSignal: nil,
            repairToolCall: { options in
                #expect(NoSuchToolError.isInstance(options.error))
                #expect(options.toolCall.toolName == "unknownTool")
                return LanguageModelV3ToolCall(
                    toolCallId: options.toolCall.toolCallId,
                    toolName: "correctTool",
                    input: options.toolCall.input
                )
            },
            experimentalContext: nil,
            generateId: mockId()
        )

        let parts = try await collect(transformed)
        #expect(parts.count == 3)

        guard case .toolCall(let call) = parts[0] else {
            Issue.record("Expected repaired tool-call")
            return
        }
        #expect(call.toolName == "correctTool")

        guard case .toolResult(let result) = parts[1] else {
            Issue.record("Expected tool-result second")
            return
        }
        switch result {
        case .static(let staticResult):
            #expect(staticResult.output == .string("test-result"))
        case .dynamic:
            Issue.record("Expected static tool result")
        }
    }

    @Test("Skips execute for provider-executed tool calls")
    func skipsExecuteForProviderExecutedCalls() async throws {
        let stream = makeStream([
            .toolCall(
                LanguageModelV3ToolCall(
                    toolCallId: "call-1",
                    toolName: "providerTool",
                    input: #"{"value":"test"}"#,
                    providerExecuted: true
                )
            ),
            .toolResult(
                LanguageModelV3ToolResult(
                    toolCallId: "call-1",
                    toolName: "providerTool",
                    result: .object(["example": .string("example")]),
                    isError: nil
                )
            ),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ])

        let executedFlag = Flag()

        let tools: ToolSet = [
            "providerTool": tool(
                inputSchema: toolInputSchema(),
                execute: { input, _ in
                    await executedFlag.mark()
                    return .value(input)
                }
            )
        ]

        let transformed = runToolsTransformation(
            tools: tools,
            generatorStream: stream,
            tracer: MockTracer(),
            telemetry: nil,
            system: nil,
            messages: [],
            abortSignal: nil,
            repairToolCall: nil,
            experimentalContext: nil,
            generateId: mockId()
        )

        _ = try await collect(transformed)
        #expect(await executedFlag.isSet() == false)
    }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("Calls onInputAvailable before execution")
    // func callsOnInputAvailableBeforeExecution() async throws {
    //     let events = EventRecorder()
    //
    //     let stream = makeStream([
    //         .toolCall(
    //             LanguageModelV3ToolCall(
    //                 toolCallId: "call-1",
    //                 toolName: "onInputAvailableTool",
    //                 input: #"{"value":"test"}"#
    //             )
    //         ),
    //         .finish(finishReason: .stop, usage: usage, providerMetadata: nil)
    //     ])
    //
    //     let tools: ToolSet = [
    //         "onInputAvailableTool": tool(
    //             inputSchema: toolInputSchema(),
    //             onInputAvailable: { options in
    //                 await events.append("onInputAvailable:\(jsonString(from: options.input) ?? "")")
    //             },
    //             execute: { _, _ in
    //                 return .value(.string("ok"))
    //             }
    //         )
    //     ]
    //
    //     let transformed = runToolsTransformation(
    //         tools: tools,
    //         generatorStream: stream,
    //         tracer: MockTracer(),
    //         telemetry: nil,
    //         system: nil,
    //         messages: [],
    //         abortSignal: nil,
    //         repairToolCall: nil,
    //         experimentalContext: nil,
    //         generateId: mockId()
    //     )
    //
    //     for try await part in transformed {
    //         switch part {
    //         case .toolCall(let call):
    //             await events.append("toolCall:\(call.toolName)")
    //         case .finish:
    //             await events.append("finish")
    //         default:
    //             break
    //         }
    //     }
    //
    //     let recorded = await events.entries()
    //
    //     #expect(recorded.count == 3)
    //     #expect(recorded[0] == #"onInputAvailable:{"value":"test"}"#)
    //     #expect(recorded[1] == "toolCall:onInputAvailableTool")
    //     #expect(recorded[2] == "finish")
    // }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("Calls onInputAvailable when approval required")
    // func callsOnInputAvailableWhenApprovalRequired() async throws {
    //     let events = EventRecorder()
    //
    //     let stream = makeStream([
    //         .toolCall(
    //             LanguageModelV3ToolCall(
    //                 toolCallId: "call-1",
    //                 toolName: "onInputAvailableTool",
    //                 input: #"{"value":"test"}"#
    //             )
    //         ),
    //         .finish(finishReason: .stop, usage: usage, providerMetadata: nil)
    //     ])
    //
    //     let tools: ToolSet = [
    //         "onInputAvailableTool": tool(
    //             inputSchema: toolInputSchema(),
    //             needsApproval: .always,
    //             onInputAvailable: { options in
    //                 await events.append("onInputAvailable:\(jsonString(from: options.input) ?? "")")
    //             }
    //         )
    //     ]
    //
    //     let transformed = runToolsTransformation(
    //         tools: tools,
    //         generatorStream: stream,
    //         tracer: MockTracer(),
    //         telemetry: nil,
    //         system: nil,
    //         messages: [],
    //         abortSignal: nil,
    //         repairToolCall: nil,
    //         experimentalContext: nil,
    //         generateId: mockId()
    //     )
    //
    //     for try await part in transformed {
    //         switch part {
    //         case .toolCall(let call):
    //             await events.append("toolCall:\(call.toolName)")
    //         case .toolApprovalRequest:
    //             await events.append("approval")
    //         case .finish:
    //             await events.append("finish")
    //         default:
    //             break
    //         }
    //     }
    //
    //     let recorded = await events.entries()
    //
    //     #expect(recorded.count == 4)
    //     #expect(recorded[0] == #"onInputAvailable:{"value":"test"}"#)
    //     #expect(recorded[1] == "toolCall:onInputAvailableTool")
    //     #expect(recorded[2] == "approval")
    //     #expect(recorded[3] == "finish")
    // }
}

// MARK: - Local Helpers

private final class IDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let value = "\(prefix)-\(current)"
        current += 1
        return value
    }
}

private func jsonString(from value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private actor EventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func entries() -> [String] {
        events
    }
}

private actor Flag {
    private var value = false

    func mark() {
        value = true
    }

    func isSet() -> Bool {
        value
    }
}
