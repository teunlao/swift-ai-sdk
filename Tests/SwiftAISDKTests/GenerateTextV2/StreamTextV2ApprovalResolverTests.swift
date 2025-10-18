import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – approval resolver")
struct StreamTextV2ApprovalResolverTests {
    @Test("resolver approve executes tool and emits tool-result (V2)")
    func resolverApproveEmitsResult() async throws {
        // Provider: client tool call then finish(toolCalls)
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "echo",
            input: "{\"v\":\"OK\"}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(finishReason: .toolCalls, usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }; c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        // Tool: echo returns value
        let tools: ToolSet = [
            "echo": tool(
                description: "Echo",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { input, _ in .value(input) }
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .approve }
        )

        let chunks = try await result.collectFullStream()
        // Expect tool-result and no approval-request
        let sawApproval = chunks.contains { if case .toolApprovalRequest = $0 { return true } else { return false } }
        let sawToolResult = chunks.contains { if case .toolResult = $0 { return true } else { return false } }
        #expect(!sawApproval && sawToolResult)
    }

    @Test("resolver approve streams preliminary then final (V2)")
    func resolverApproveStreamsPreliminary() async throws {
        // Provider: client tool call then finish(toolCalls)
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "streamer",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(finishReason: .toolCalls, usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }; c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        // Tool: emits 3 chunks, then completes
        let streamingTool = tool(
            description: "Streamer",
            inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
            needsApproval: .always,
            execute: { _, _ in
                let (s, cont) = AsyncThrowingStream<JSONValue, Error>.makeStream()
                Task {
                    cont.yield(.string("a"))
                    cont.yield(.string("b"))
                    cont.yield(.string("c"))
                    cont.finish()
                }
                return .stream(s)
            }
        )
        let tools: ToolSet = ["streamer": streamingTool]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .approve }
        )

        let chunks = try await result.collectFullStream()
        // Count preliminary results and ensure final exists
        var prelimCount = 0
        var sawFinal = false
        for part in chunks {
            if case let .toolResult(res) = part {
                switch res {
                case .static(let r):
                    if r.preliminary == true { prelimCount += 1 } else { sawFinal = true }
                case .dynamic(let r):
                    if r.preliminary == true { prelimCount += 1 } else { sawFinal = true }
                }
            }
        }
        #expect(prelimCount == 3)
        #expect(sawFinal)
    }

    @Test("resolver deny emits tool-output-denied (V2)")
    func resolverDenyEmitsDenied() async throws {
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "noop",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(finishReason: .toolCalls, usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }; c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        let tools: ToolSet = [
            "noop": tool(
                description: "No-op",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .deny }
        )

        let chunks = try await result.collectFullStream()
        let sawDenied = chunks.contains { if case .toolOutputDenied = $0 { return true } else { return false } }
        #expect(sawDenied)
    }

    @Test("resolver handles multiple approvals in step (V2)")
    func resolverHandlesMultipleApprovals() async throws {
        let call1 = LanguageModelV3ToolCall(
            toolCallId: "a1",
            toolName: "alpha",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let call2 = LanguageModelV3ToolCall(
            toolCallId: "b2",
            toolName: "beta",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call1),
            .toolCall(call2),
            .finish(
                finishReason: .toolCalls,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
                providerMetadata: nil
            )
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        actor ApprovalRecorder {
            private var values: [String] = []
            func append(_ value: String) {
                values.append(value)
            }
            func snapshot() -> [String] { values }
        }
        let recorder = ApprovalRecorder()

        let tools: ToolSet = [
            "alpha": tool(
                description: "Alpha",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { _, _ in .value(.string("ok-alpha")) }
            ),
            "beta": tool(
                description: "Beta",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { _, _ in .value(.string("ok-beta")) }
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { request in
                await recorder.append(request.approvalId)
                return .approve
            }
        )

        let chunks = try await result.collectFullStream()
        let toolResults = chunks.compactMap { part -> String? in
            guard case let .toolResult(res) = part else { return nil }
            switch res {
            case .static(let r): return r.toolCallId
            case .dynamic(let r): return r.toolCallId
            }
        }
        #expect(toolResults.contains("a1") && toolResults.contains("b2"))
        #expect(!chunks.contains { if case .toolApprovalRequest = $0 { return true } else { return false } })
        let approvalOrder = await recorder.snapshot()
        #expect(approvalOrder == ["a1", "b2"])
    }

    @Test("conditional approval receives context (V2)")
    func conditionalApprovalReceivesContext() async throws {
        let call = LanguageModelV3ToolCall(
            toolCallId: "ctx",
            toolName: "gamma",
            input: "{\"flag\":true}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(
                finishReason: .toolCalls,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
                providerMetadata: nil
            )
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        actor ContextProbe {
            private(set) var optionSnapshots: [ToolCallApprovalOptions] = []
            func record(_ options: ToolCallApprovalOptions) { optionSnapshots.append(options) }
            func snapshots() -> [ToolCallApprovalOptions] { optionSnapshots }
        }

        let probe = ContextProbe()

        let tools: ToolSet = [
            "gamma": tool(
                description: "Gamma",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .conditional { _, options in
                    await probe.record(options)
                    return true
                },
                execute: { _, _ in .value(.string("done")) }
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            system: nil,
            messages: [.user(UserModelMessage(content: .text("hello"), providerOptions: nil))],
            tools: tools,
            experimentalApprove: { _ in .approve }
        )

        let chunks = try await result.collectFullStream()
        #expect(chunks.contains { part in
            if case let .toolResult(res) = part {
                switch res {
                case .static(let value):
                    return value.toolCallId == "ctx"
                case .dynamic:
                    return false
                }
            }
            return false
        })

        let snapshots = await probe.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.toolCallId == "ctx")
        #expect(snapshots.first?.messages.contains(where: { message in
            if case let .user(user) = message { return user.content == .text("hello") }
            return false
        }) == true)
    }

    @Test("provider-executed tool skips resolver (V2)")
    func providerExecutedToolSkipsResolver() async throws {
        let call = LanguageModelV3ToolCall(
            toolCallId: "p1",
            toolName: "providerTool",
            input: "{}",
            providerExecuted: true,
            providerMetadata: nil
        )
        let toolResult = LanguageModelV3ToolResult(
            toolCallId: "p1",
            toolName: "providerTool",
            result: .string("done"),
            providerExecuted: true,
            preliminary: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .toolResult(toolResult),
            .finish(
                finishReason: .toolCalls,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
                providerMetadata: nil
            )
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        actor Counter {
            private var value = 0
            func increment() { value += 1 }
            func current() -> Int { value }
        }
        let counter = Counter()

        let tools: ToolSet = [
            "providerTool": tool(
                description: "Provider tool shadow",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { request in
                await counter.increment()
                return .approve
            }
        )

        let chunks = try await result.collectFullStream()
        let approvalRequests = chunks.filter { if case .toolApprovalRequest = $0 { return true } else { return false } }
        #expect(approvalRequests.isEmpty)
        #expect(await counter.current() == 0)
        #expect(chunks.contains { part in
            if case let .toolResult(res) = part {
                switch res {
                case .static(let info):
                    return info.toolCallId == "p1" && info.providerExecuted == true
                case .dynamic(let info):
                    return info.toolCallId == "p1" && info.providerExecuted == true
                }
            }
            return false
        })
    }

    @Test("needsApproval never skips resolver (V2)")
    func needsApprovalNeverSkipsResolver() async throws {
        let call = LanguageModelV3ToolCall(
            toolCallId: "n1",
            toolName: "noop",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(
                finishReason: .toolCalls,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
                providerMetadata: nil
            )
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        actor InvokeCounter {
            private var value = 0
            func increment() { value += 1 }
            func snapshot() -> Int { value }
        }

        let counter = InvokeCounter()

        let tools: ToolSet = [
            "noop": tool(
                description: "No approval needed",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .never,
                execute: { _, _ in .value(.string("ok")) }
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { request in
                await counter.increment()
                return .approve
            }
        )

        let chunks = try await result.collectFullStream()
        let approvalRequests = chunks.filter { if case .toolApprovalRequest = $0 { return true } else { return false } }
        #expect(approvalRequests.isEmpty)
        #expect(await counter.snapshot() == 0)
        let toolResults = chunks.compactMap { part -> TypedToolResult? in
            if case let .toolResult(res) = part { return res }
            return nil
        }
        let staticResult = toolResults.compactMap { result -> StaticToolResult? in
            if case let .static(info) = result { return info }
            return nil
        }
        #expect(staticResult.count == 1)
        let info = staticResult[0]
        #expect(info.toolCallId == "n1")
        #expect(info.providerExecuted == false)
        #expect(info.preliminary != true)
        #expect(info.output == .string("ok"))
    }

    @Test("streaming tool error propagates (V2)")
    func streamingToolErrorPropagates() async throws {
        let call = LanguageModelV3ToolCall(
            toolCallId: "stream-error",
            toolName: "streamer",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(
                finishReason: .toolCalls,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
                providerMetadata: nil
            )
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        struct ToolStreamError: Error {}

        let tools: ToolSet = [
            "streamer": tool(
                description: "Streaming tool that fails",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { _, _ in
                    let (stream, continuation) = AsyncThrowingStream<JSONValue, Error>.makeStream()
                    Task {
                        continuation.yield(.string("partial"))
                        continuation.finish(throwing: ToolStreamError())
                    }
                    return .stream(stream)
                }
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .approve }
        )

        let chunks = try await result.collectFullStream()
        let preliminaryCount = chunks.filter { part in
            if case let .toolResult(res) = part {
                switch res {
                case .static(let info):
                    return info.toolCallId == "stream-error" && info.preliminary == true
                case .dynamic(let info):
                    return info.toolCallId == "stream-error" && info.preliminary == true
                }
            }
            return false
        }.count
        let sawToolError = chunks.contains { part in
            if case let .toolError(error) = part {
                return error.toolCallId == "stream-error"
            }
            return false
        }
        #expect(preliminaryCount == 1)
        #expect(sawToolError)
        #expect(!chunks.contains { part in
            if case let .toolResult(res) = part {
                switch res {
                case .static(let info):
                    return info.toolCallId == "stream-error" && info.preliminary != true
                case .dynamic(let info):
                    return info.toolCallId == "stream-error" && info.preliminary != true
                }
            }
            return false
        })
    }
}
