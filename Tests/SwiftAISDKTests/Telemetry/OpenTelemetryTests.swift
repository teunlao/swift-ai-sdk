import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("OpenTelemetry GenAI contracts")
struct OpenTelemetryTests {
    private let usage = LanguageModelV4Usage(inputTokens: .init(total: 3, noCache: 1, cacheRead: 2), outputTokens: .init(total: 4, text: 3, reasoning: 1))

    private func result(_ content: [LanguageModelV4Content]) -> LanguageModelV4GenerateResult {
        LanguageModelV4GenerateResult(content: content, finishReason: .init(unified: .stop), usage: usage)
    }

    @Test("supplemental attributes are opt-in while GenAI attributes and custom enrichment remain available", arguments: [false, true])
    func supplementalAttributes(enabled: Bool) async throws {
        let tracer = MockTracer()
        let integration = OpenTelemetry(tracer: tracer, enrichSpan: { event in
            ["app.type": .string(event.spanType.rawValue), "gen_ai.operation.name": .string("overridden"), "app.invalid": .double(.infinity)]
        }, usage: enabled, providerMetadata: enabled, runtimeContext: enabled, headers: enabled)
        let model = MockLanguageModelV4(provider: "google.vertex.chat", doGenerate: .singleValue(
            LanguageModelV4GenerateResult(content: [.text(.init(text: "ok"))], finishReason: .init(unified: .stop), usage: usage,
                providerMetadata: ["example": ["trace": .string("123")]])
        ))
        _ = try await generateText(model: model, instructions: .text("Be brief"), messages: [
            .user(.init(content: .parts([.text(.init(text: "hello")), .image(.init(image: .data(Data([1, 2, 3])), mediaType: "image/png"))])))
        ], telemetry: TelemetryOptions(includeRuntimeContext: ["tenant": true], integrations: [integration]),
            runtimeContext: ["tenant": .object(["id": .string("acme")]), "secret": .string("hidden")],
            settings: CallSettings(headers: ["x-request": "123"]))

        let spans = tracer.spanRecords
        let root = try #require(spans.first)
        let inference = try #require(spans.last)
        #expect(root.attributes["gen_ai.provider.name"] == .string("gcp.vertex_ai"))
        #expect(root.attributes["gen_ai.operation.name"] == .string("invoke_agent"))
        #expect(root.attributes["app.type"] == .string("operation"))
        #expect(root.attributes["app.invalid"] == nil)
        #expect(root.attributes["gen_ai.system_instructions"] == .string(#"[{"content":"Be brief","type":"text"}]"#))
        let input = try jsonAttribute(root, "gen_ai.input.messages")
        #expect(input == .array([.object(["role": .string("user"), "parts": .array([
            .object(["type": .string("text"), "content": .string("hello")]),
            .object(["type": .string("blob"), "modality": .string("image"), "mime_type": .string("image/png"), "content": .string("AQID")]),
        ])])]))
        #expect(inference.attributes["gen_ai.usage.cache_read.input_tokens"] == .int(2))
        #expect(root.attributes["ai.request.headers.x-request"] == (enabled ? .string("123") : nil))
        #expect(root.attributes["ai.settings.context.tenant.id"] == (enabled ? .string("acme") : nil))
        #expect(root.attributes["ai.settings.context.secret"] == nil)
        #expect(inference.attributes["ai.usage.outputTokenDetails.reasoningTokens"] == (enabled ? .int(1) : nil))
        #expect(inference.attributes["ai.response.providerMetadata"] == (enabled ? .string(#"{"example":{"trace":"123"}}"#) : nil))
    }

    @Test("provider-executed tools are children of inference with extension definitions and results")
    func providerTool() async throws {
        let tracer = MockTracer()
        let model = MockLanguageModelV4(provider: "openai.responses", doGenerate: .singleValue(result([
            .toolCall(.init(toolCallId: "search-1", toolName: "search", input: #"{"query":"swift"}"#, providerExecuted: true, dynamic: true)),
            .toolResult(.init(toolCallId: "search-1", toolName: "search", result: .string("found"), dynamic: true)),
            .text(.init(text: "answer")),
        ])))
        _ = try await generateText(model: model, prompt: "search", telemetry: TelemetryOptions(integrations: [OpenTelemetry(tracer: tracer)]))
        let spans = tracer.spanRecords
        let inference = try #require(spans.first { $0.name == "chat mock-model-id" })
        let tool = try #require(spans.first { $0.name == "execute_tool search" })
        #expect(tool.parentId == inference.spanId)
        #expect(tool.attributes["gen_ai.tool.type"] == .string("extension"))
        #expect(tool.attributes["gen_ai.tool.call.arguments"] == .string(#"{"query":"swift"}"#))
        #expect(tool.attributes["gen_ai.tool.call.result"] == .string(#""found""#))
        let definitions = try jsonAttribute(inference, "gen_ai.tool.definitions")
        #expect(definitions == .array([.object(["type": .string("extension"), "name": .string("search")])]))
        let ended = spans.allSatisfy { $0.ended }
        #expect(ended)
    }

    @Test("nested generations inherit the executing tool span")
    func nestedGeneration() async throws {
        let tracer = MockTracer()
        let integration = OpenTelemetry(tracer: tracer)
        let inner = MockLanguageModelV4(modelId: "inner", doGenerate: .singleValue(result([.text(.init(text: "nested"))])))
        let outer = MockLanguageModelV4(modelId: "outer", doGenerate: .singleValue(result([
            .toolCall(.init(toolCallId: "call", toolName: "nested", input: "{}")),
        ])))
        let schema: FlexibleSchema<JSONValue> = FlexibleSchema(jsonSchema(.object(["type": .string("object")])))
        _ = try await generateText(model: outer, tools: ["nested": tool(inputSchema: schema, execute: { _, _ in
            let result = try await generateText(model: inner, prompt: "nested", telemetry: TelemetryOptions(integrations: [integration]))
            return .value(.string(result.text))
        })], prompt: "go", telemetry: TelemetryOptions(integrations: [integration]))
        let spans = tracer.spanRecords
        let tool = try #require(spans.first { $0.name == "execute_tool nested" })
        let nested = try #require(spans.first { $0.name == "invoke_agent inner" })
        #expect(nested.parentId == tool.spanId)
        #expect(tool.attributes["gen_ai.tool.call.result"] == .string(#""nested""#))
        let ended = spans.allSatisfy { $0.ended }
        #expect(ended)
    }

    @Test("provider failure ends and marks every open generation span")
    func providerFailure() async throws {
        struct Failure: Error {}
        let tracer = MockTracer()
        let model = MockLanguageModelV4(doGenerate: .function { _ in throw Failure() })
        await #expect(throws: Failure.self) {
            try await generateText(model: model, prompt: "go", telemetry: TelemetryOptions(integrations: [OpenTelemetry(tracer: tracer)]), settings: CallSettings(maxRetries: 0))
        }
        #expect(tracer.spanRecords.count == 3)
        #expect(tracer.spanRecords.allSatisfy { $0.ended && $0.status?.code == .error && $0.events.contains { $0.name == "exception" } })
    }

    private func jsonAttribute(_ span: MockTracer.SpanRecord, _ key: String) throws -> JSONValue {
        let attribute = try #require(span.attributes[key])
        guard case .string(let json) = attribute else { Issue.record("Expected JSON attribute"); return .null }
        return try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }
}
