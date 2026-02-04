import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("executeToolCall – providerMetadata")
struct ExecuteToolCallProviderMetadataTests {
    private let schema = FlexibleSchema(jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "q": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("q")]),
            "additionalProperties": .bool(false),
        ])
    ))

    @Test("tool-result copies providerMetadata from tool call")
    func toolResultCopiesProviderMetadata() async {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]

        let tools: ToolSet = [
            "demo": Tool(
                description: "Demo",
                inputSchema: schema,
                execute: { _, _ in .value(.object(["ok": .bool(true)])) }
            )
        ]

        let call = TypedToolCall.static(StaticToolCall(
            toolCallId: "c1",
            toolName: "demo",
            input: .object(["q": .string("hi")]),
            providerMetadata: meta
        ))

        let output = await executeToolCall(
            toolCall: call,
            tools: tools,
            tracer: MockTracer(),
            telemetry: nil,
            messages: [],
            abortSignal: nil,
            experimentalContext: nil
        )

        guard let output else {
            Issue.record("Expected tool output.")
            return
        }

        if case .result(let result) = output {
            #expect(result.providerMetadata == meta)
        } else {
            Issue.record("Expected tool result.")
        }
    }

    @Test("tool-error copies providerMetadata from tool call")
    func toolErrorCopiesProviderMetadata() async {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]

        let tools: ToolSet = [
            "demo": Tool(
                description: "Demo",
                inputSchema: schema,
                execute: { _, _ in
                    throw NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
                }
            )
        ]

        let call = TypedToolCall.static(StaticToolCall(
            toolCallId: "c1",
            toolName: "demo",
            input: .object(["q": .string("hi")]),
            providerMetadata: meta
        ))

        let output = await executeToolCall(
            toolCall: call,
            tools: tools,
            tracer: MockTracer(),
            telemetry: nil,
            messages: [],
            abortSignal: nil,
            experimentalContext: nil
        )

        guard let output else {
            Issue.record("Expected tool output.")
            return
        }

        if case .error(let error) = output {
            #expect(error.providerMetadata == meta)
        } else {
            Issue.record("Expected tool error.")
        }
    }
}

