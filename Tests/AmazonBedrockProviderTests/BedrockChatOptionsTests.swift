import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AmazonBedrockProvider

@Suite("Bedrock Converse V4 contracts")
struct BedrockChatOptionsTests {
    @Test("Non-Anthropic budget never enters reasoningConfig alongside effort")
    func nonAnthropicBudget() async throws {
        let server = try BedrockTestServer()
        let result = try await server.provider().chat(modelId: "amazon.nova-2-lite-v1:0").doGenerate(options: .init(prompt: [], maxOutputTokens: 100, providerOptions: ["amazonBedrock": ["reasoningConfig": .object(["type": .string("enabled"), "budgetTokens": .number(1024), "maxReasoningEffort": .string("high")])]]))
        let body = try await server.requestBody()
        #expect(body["additionalModelRequestFields"]?["reasoningConfig"] == .object(["type": .string("enabled"), "maxReasoningEffort": .string("high")]))
        #expect(body["inferenceConfig"] == nil)
        let features = result.warnings.compactMap { if case .unsupported(let feature, _) = $0 { return feature }; return nil }
        #expect(features.contains("budgetTokens"))
        #expect(features.contains("maxOutputTokens"))
    }

    @Test("Portable reasoning maps to OpenAI and Nova request formats", arguments: ["us.openai.gpt-oss-120b-1:0", "us.openai.gpt-5", "us.amazon.nova-2-lite-v1:0"])
    func portableReasoning(_ id: String) async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: .init(rawValue: id)).doGenerate(options: .init(prompt: [], temperature: 1.4, stopSequences: ["stop"], reasoning: .xhigh))
        let body = try await server.requestBody()
        if id.contains("gpt-oss") {
            #expect(body["additionalModelRequestFields"]?["reasoning_effort"] == .string("max"))
            #expect(body["inferenceConfig"]?["temperature"] == .number(1))
            #expect(body["inferenceConfig"]?["stopSequences"] == nil)
        } else if id.contains("openai") {
            #expect(body["additionalModelRequestFields"]?["reasoning"] == .object(["effort": .string("max")]))
            #expect(body["inferenceConfig"] == nil)
        } else {
            #expect(body["additionalModelRequestFields"]?["reasoningConfig"] == .object(["type": .string("enabled"), "maxReasoningEffort": .string("high")]))
        }
    }

    @Test("Anthropic portable adaptive reasoning merges existing output configuration")
    func adaptiveReasoning() async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: "anthropic.claude-opus-4-6-v1").doGenerate(options: .init(prompt: [], temperature: 0.5, topP: 0.8, topK: 10, reasoning: .high, providerOptions: ["amazonBedrock": ["reasoningConfig": .object(["display": .string("omitted")]), "additionalModelRequestFields": .object(["output_config": .object(["other": .string("kept")])])]]))
        let body = try await server.requestBody()
        #expect(body["additionalModelRequestFields"]?["thinking"] == .object(["type": .string("adaptive"), "display": .string("omitted")]))
        #expect(body["additionalModelRequestFields"]?["output_config"]?["effort"] == .string("high"))
        #expect(body["additionalModelRequestFields"]?["output_config"]?["other"] == .string("kept"))
        #expect(body["inferenceConfig"] == nil)
    }

    @Test("Application profile budget selects Anthropic reasoning and canonical options win")
    func applicationProfile() async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: "arn:aws:bedrock:us-east-1:123:application-inference-profile/opaque").doGenerate(options: .init(prompt: [], maxOutputTokens: 50, providerOptions: [
            "amazonBedrock": ["reasoningConfig": .object(["type": .string("enabled"), "budgetTokens": .number(1024)]), "serviceTier": .string("priority"), "requestMetadata": .object(["project": .string("p")])],
            "bedrock": ["serviceTier": .string("flex")]
        ]))
        let body = try await server.requestBody()
        #expect(body["inferenceConfig"]?["maxTokens"] == .number(1074))
        #expect(body["additionalModelRequestFields"]?["thinking"] == .object(["type": .string("enabled"), "budget_tokens": .number(1024)]))
        #expect(body["serviceTier"] == .object(["type": .string("priority")]))
        #expect(body["requestMetadata"] == .object(["project": .string("p")]))
        #expect(body["reasoningConfig"] == nil)
    }

    @Test("Native structured outputs, JSON tools and instruction mode respect model capabilities", arguments: ["anthropic.claude-opus-4-6-v1", "anthropic.claude-haiku-4-5-20251001-v1:0", "anthropic.claude-sonnet-5-5"])
    func structuredOutputs(_ id: String) async throws {
        let server = try BedrockTestServer()
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["answer": .object(["type": .string("string")])]), "additionalProperties": .bool(false)])
        _ = try await server.provider().chat(modelId: .init(rawValue: id)).doGenerate(options: .init(prompt: [.user(content: [.text(.init(text: "Answer"))], providerOptions: nil)], responseFormat: .json(schema: schema, name: nil, description: nil)))
        let body = try await server.requestBody()
        if id.contains("opus-4-6") {
            #expect(body["additionalModelRequestFields"]?["output_config"]?["format"]?["type"] == .string("json_schema"))
            #expect(body["toolConfig"] == nil)
        } else if id.contains("haiku-4-5") {
            #expect(body["toolConfig"]?["tools"]?.array.first?["toolSpec"]?["name"] == .string("json"))
            #expect(body["toolConfig"]?["toolChoice"] == .object(["any": .object([:])]))
        } else {
            #expect(body["toolConfig"] == nil)
            #expect(body["system"]?.array.count == 1)
        }
    }

    @Test("Generate preserves raw usage and returns both reasoning metadata namespaces")
    func generatedMetadata() async throws {
        let raw: JSONValue = .object(["inputTokens": .number(10), "outputTokens": .number(5), "totalTokens": .number(15), "cacheReadInputTokens": .number(2), "cacheWriteInputTokens": .number(3), "future": .object(["extra": .number(99)])])
        let server = try BedrockTestServer(json: .object([
            "output": .object(["message": .object(["role": .string("assistant"), "content": .array([
                .object(["citationsContent": .object(["content": .array([.object(["text": .string("citation text")])])])]),
                .object(["reasoningContent": .object(["redactedContent": .string("encrypted")])]),
                .object(["toolUse": .object(["toolUseId": .string("ééééééééé"), "name": .string("lookup"), "input": .object([:])])])
            ])])]), "stopReason": .string("tool_use"), "usage": raw, "serviceTier": .object(["type": .string("priority")])
        ]), headers: ["x-amzn-requestid": "req"])
        let result = try await server.provider().chat(modelId: "mistral.large").doGenerate(options: .init(prompt: []))
        #expect(result.usage.raw == raw)
        #expect(result.usage.inputTokens.total == 15)
        #expect(result.content.first == .text(.init(text: "citation text")))
        #expect(result.content[1] == .reasoning(.init(text: "", providerMetadata: ["amazonBedrock": ["redactedContent": .string("encrypted")], "bedrock": ["redactedContent": .string("encrypted")]])))
        guard case .toolCall(let tool) = result.content.last else { Issue.record("Expected tool call"); return }
        #expect(tool.toolCallId.range(of: "\\A[a-zA-Z0-9]{9}\\z", options: .regularExpression) != nil)
        #expect(result.finishReason.unified == .toolCalls)
        #expect(result.providerMetadata?["amazonBedrock"] == result.providerMetadata?["bedrock"])
        #expect(result.response?.id == "req")
    }

    @Test("Encrypted stream reasoning joins fragments on reasoning-end")
    func encryptedStreamReasoning() async throws {
        let frames = try [
            BedrockTestEventStream.jsonMessage(eventType: "contentBlockDelta", payload: ["contentBlockIndex": 0, "delta": ["reasoningContent": ["redactedContent": "first"]]]),
            BedrockTestEventStream.jsonMessage(eventType: "contentBlockDelta", payload: ["contentBlockIndex": 0, "delta": ["reasoningContent": ["redactedContent": "second"]]]),
            BedrockTestEventStream.jsonMessage(eventType: "contentBlockStop", payload: ["contentBlockIndex": 0]),
            BedrockTestEventStream.jsonMessage(eventType: "messageStop", payload: ["stopReason": "end_turn"])
        ]
        let server = BedrockTestServer(data: frames.reduce(into: Data()) { $0.append($1) })
        let result = try await server.provider().chat(modelId: "openai.gpt-5").doStream(options: .init(prompt: [], includeRawChunks: true))
        let parts = try await convertReadableStreamToArray(result.stream)
        #expect(parts.contains(.reasoningStart(id: "0", providerMetadata: nil)))
        #expect(parts.contains(.reasoningEnd(id: "0", providerMetadata: ["amazonBedrock": ["redactedContent": .string("firstsecond")], "bedrock": ["redactedContent": .string("firstsecond")]])))
        #expect(parts.filter { if case .reasoningDelta = $0 { return true }; return false }.isEmpty)
    }

    @Test("Stream exceptions carry typed retry metadata", arguments: [("serviceUnavailableException", 503, true), ("validationException", 400, false)])
    func streamExceptions(_ type: String, _ status: Int, _ retryable: Bool) async throws {
        let frame = BedrockTestEventStream.frame(headers: [":message-type": "exception", ":exception-type": type], body: Data("{\"message\":\"failure\"}".utf8))
        let server = BedrockTestServer(data: frame)
        let stream = try await server.provider().chat(modelId: "amazon.nova-pro-v1:0").doStream(options: .init(prompt: []))
        let parts = try await convertReadableStreamToArray(stream.stream)
        guard case .error(.providerStreamError(let error)) = parts.dropFirst(2).first else { Issue.record("Expected typed provider stream error"); return }
        #expect(error.message == "failure")
        #expect(error.type == type)
        #expect(error.statusCode == status)
        #expect(error.isRetryable == retryable)
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("Expected finish"); return }
        #expect(reason.unified == .error)
    }
}
