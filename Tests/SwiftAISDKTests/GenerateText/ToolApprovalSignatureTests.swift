import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

private actor IntCounter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }

    func current() -> Int { value }
}

@Suite("Tool approval signatures")
struct ToolApprovalSignatureTests {
    private let usage = LanguageModelV3Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))

    private func approvalTool(executions: IntCounter) -> ToolSet {
        [
            "tool1": tool(
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object"),
                    "properties": .object(["value": .object(["type": .string("string")])]),
                    "required": .array([.string("value")]),
                    "additionalProperties": .bool(false),
                ]))),
                needsApproval: .always,
                execute: { _, _ in
                    _ = await executions.next()
                    return .value(.string("done"))
                }
            )
        ]
    }

    /// History after a signed approval request was issued and approved by the user.
    private func approvedHistory(secret: ToolApprovalSecret, tools: ToolSet) async throws -> [ModelMessage] {
        let model = MockLanguageModelV3(doGenerate: .singleValue(LanguageModelV3GenerateResult(
            content: [.toolCall(LanguageModelV3ToolCall(toolCallId: "call-1", toolName: "tool1", input: #"{"value":"v"}"#))],
            finishReason: .toolCalls,
            usage: usage
        )))
        let issued = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "run it",
            toolApprovalSecret: secret
        )
        let request = try #require(issued.content.compactMap { part -> ToolApprovalRequestOutput? in
            if case .toolApprovalRequest(let request) = part { return request }
            return nil
        }.first)
        #expect(request.signature != nil)

        let user = ModelMessage.user(UserModelMessage(content: .text("run it")))
        let approval = ModelMessage.tool(ToolModelMessage(content: [
            .toolApprovalResponse(ToolApprovalResponse(approvalId: request.approvalId, approved: true)),
        ]))
        return [user] + issued.responseMessages.map(\.modelMessage) + [approval]
    }

    private func continueFrom(_ messages: [ModelMessage], secret: ToolApprovalSecret, tools: ToolSet) async throws {
        let model = MockLanguageModelV3(doGenerate: .singleValue(LanguageModelV3GenerateResult(
            content: [.text(LanguageModelV3Text(text: "ok"))],
            finishReason: .stop,
            usage: usage
        )))
        _ = try await generateText(model: .v3(model), tools: tools, messages: messages, toolApprovalSecret: secret)
    }

    @Test("a signed approval issued by the server executes when it comes back approved")
    func signedApprovalExecutes() async throws {
        let executions = IntCounter()
        let tools = approvalTool(executions: executions)
        let history = try await approvedHistory(secret: "server-secret", tools: tools)

        try await continueFrom(history, secret: "server-secret", tools: tools)

        #expect(await executions.current() == 1)
    }

    @Test("a forged, tampered or unsigned approval is rejected before execution")
    func invalidApprovalsAreRejected() async throws {
        let executions = IntCounter()
        let tools = approvalTool(executions: executions)
        let history = try await approvedHistory(secret: "server-secret", tools: tools)

        let tampered = history.map { message -> ModelMessage in
            guard case .assistant(let assistant) = message, case .parts(let parts) = assistant.content else { return message }
            return .assistant(AssistantModelMessage(content: .parts(parts.map { part in
                guard case .toolCall(let call) = part else { return part }
                return .toolCall(ToolCallPart(
                    toolCallId: call.toolCallId,
                    toolName: call.toolName,
                    input: .object(["value": .string("rm -rf /")])
                ))
            })))
        }
        let unsigned = history.map { message -> ModelMessage in
            guard case .assistant(let assistant) = message, case .parts(let parts) = assistant.content else { return message }
            return .assistant(AssistantModelMessage(content: .parts(parts.map { part in
                guard case .toolApprovalRequest(let request) = part else { return part }
                return .toolApprovalRequest(ToolApprovalRequest(approvalId: request.approvalId, toolCallId: request.toolCallId))
            })))
        }

        for (messages, secret, reason) in [
            (history, ToolApprovalSecret("another-secret"), "invalid signature"),
            (tampered, ToolApprovalSecret("server-secret"), "invalid signature"),
            (unsigned, ToolApprovalSecret("server-secret"), "missing signature"),
        ] {
            let error = await #expect(throws: InvalidToolApprovalSignatureError.self) {
                try await continueFrom(messages, secret: secret, tools: tools)
            }
            #expect(error?.message.hasSuffix(reason) == true)
        }
        #expect(await executions.current() == 0)
    }
}

@Suite("Tool fingerprints")
struct ToolFingerprintTests {
    private func weatherTool(description: ToolDescription?, property: String = "city") -> Tool {
        tool(
            description: description,
            inputSchema: FlexibleSchema(jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([property: .object(["type": .string("string")])]),
            ])))
        )
    }

    @Test("drift reports added, removed and changed definitions; resolved descriptions are not pinned")
    func detectsDrift() async throws {
        let baseline = try await fingerprintTools([
            "weather": weatherTool(description: "Get the weather"),
            "search": weatherTool(description: .resolve { _ in "first" }),
            "old": weatherTool(description: nil),
        ])
        let current = try await fingerprintTools([
            "weather": weatherTool(description: "Get the weather", property: "town"),
            "search": weatherTool(description: .resolve { _ in "second" }),
            "new": weatherTool(description: nil),
        ])

        #expect(detectToolDrift(current: current, baseline: baseline) == ToolDrift(
            added: ["new"],
            removed: ["old"],
            changed: ["weather"]
        ))
        #expect(detectToolDrift(current: baseline, baseline: baseline) == ToolDrift(added: [], removed: [], changed: []))
    }
}
