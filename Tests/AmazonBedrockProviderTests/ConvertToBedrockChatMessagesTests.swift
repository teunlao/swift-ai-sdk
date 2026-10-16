import Foundation
import Testing
import AISDKProvider
import AmazonBedrockProvider

@Suite("Bedrock message HTTP contracts")
struct ConvertToBedrockChatMessagesTests {
    private let tool = LanguageModelV4Tool.function(.init(name: "lookup", inputSchema: .object(["type": .string("object")])))

    @Test("Leading systems and part-level cache points retain order")
    func systemsAndCache() async throws {
        let server = try BedrockTestServer()
        let model = server.provider().chat(modelId: "amazon.nova-pro-v1:0")
        _ = try await model.doGenerate(options: .init(prompt: [
            .system(content: "First", providerOptions: ["amazonBedrock": ["cachePoint": .object(["type": .string("default"), "ttl": .string("1h")])]]),
            .system(content: "Second", providerOptions: nil),
            .user(content: [.text(.init(text: "Question", providerOptions: ["bedrock": ["cachePoint": .object(["type": .string("default")])]]))], providerOptions: nil)
        ]))
        let body = try await server.requestBody()
        #expect(body["system"]?.array == [.object(["text": .string("First")]), .object(["cachePoint": .object(["type": .string("default"), "ttl": .string("1h")])]), .object(["text": .string("Second")])])
        #expect(body["messages"]?.array.first?["content"]?.array.last == .object(["cachePoint": .object(["type": .string("default")])]))
    }

    @Test("A system after user content is rejected at the model boundary")
    func misplacedSystem() async throws {
        let model = try BedrockTestServer().provider().chat(modelId: "amazon.nova-pro-v1:0")
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(options: .init(prompt: [.user(content: [.text(.init(text: "hello"))], providerOptions: nil), .system(content: "late", providerOptions: nil)]))
        }
    }

    @Test("Mistral tool identifiers hash to ASCII base62 and pair calls with results")
    func mistralToolRoundTrip() async throws {
        let server = try BedrockTestServer()
        let raw = "tooluse_bpe71yCfRu2b5i-nKGDr5g"
        _ = try await server.provider().chat(modelId: "us.mistral.pixtral-large-2502-v1:0").doGenerate(options: .init(prompt: [
            .assistant(content: [.toolCall(.init(toolCallId: raw, toolName: "look.up!?", input: .string("invalid")))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: raw, toolName: "lookup", output: .json(value: .number(42))))], providerOptions: nil)
        ], tools: [tool]))
        let messages = try await server.requestBody()["messages"]?.array ?? []
        let call = messages.first?["content"]?.array.first?["toolUse"]
        let result = messages.last?["content"]?.array.first?["toolResult"]
        guard case .string(let id)? = call?["toolUseId"] else { Issue.record("Missing tool call id"); return }
        #expect(id.range(of: "\\A[a-zA-Z0-9]{9}\\z", options: .regularExpression) != nil)
        #expect(result?["toolUseId"] == .string(id))
        #expect(call?["name"] == .string("lookup"))
        #expect(call?["input"] == .object(["rawInvalidInput": .string("invalid")]))
        #expect(result?["content"] == .array([.object(["text": .string("42")])]))
    }

    @Test("Signed and encrypted reasoning is replayed, unsigned reasoning is withheld")
    func reasoningReplay() async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: "us.openai.gpt-oss-120b-1:0").doGenerate(options: .init(prompt: [
            .assistant(content: [
                .reasoning(.init(text: "private unsigned")),
                .reasoning(.init(text: "signed bytes  ", providerOptions: ["amazonBedrock": ["signature": .string("sig")]])),
                .reasoning(.init(text: "", providerOptions: ["bedrock": ["redactedContent": .string("encrypted")]])),
                .text(.init(text: "answer  "))
            ], providerOptions: nil)
        ]))
        let content = try await server.requestBody()["messages"]?.array.first?["content"]?.array ?? []
        #expect(content == [
            .object(["reasoningContent": .object(["reasoningText": .object(["text": .string("signed bytes  "), "signature": .string("sig")])])]),
            .object(["reasoningContent": .object(["redactedContent": .string("encrypted")])]),
            .object(["text": .string("answer")])
        ])
    }

    @Test("Assistant tool results and following user content share the user turn")
    func assistantToolResults() async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: "amazon.nova-pro-v1:0").doGenerate(options: .init(prompt: [
            .assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "lookup", input: .object([:]))), .toolResult(.init(toolCallId: "call", toolName: "lookup", output: .text(value: "result")))], providerOptions: nil),
            .user(content: [.text(.init(text: "continue"))], providerOptions: nil)
        ], tools: [tool]))
        let messages = try await server.requestBody()["messages"]?.array ?? []
        #expect(messages.count == 2)
        #expect(messages.last?["role"] == .string("user"))
        #expect(messages.last?["content"]?.array.count == 2)
        #expect(messages.last?["content"]?.array.last == .object(["text": .string("continue")]))
    }

    @Test("S3 media, textual documents and guardrail content use Bedrock wire types")
    func mediaAndGuardrails() async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider().chat(modelId: "amazon.nova-pro-v1:0").doGenerate(options: .init(prompt: [.user(content: [
            .text(.init(text: "ground", providerOptions: ["amazonBedrock": ["guardContent": .bool(true), "guardContentQualifiers": .array([.string("grounding_source")])]])),
            .file(.init(data: .url(try #require(URL(string: "s3://bucket/clip.mp4"))), mediaType: "video/mp4")),
            .file(.init(data: .text("document body"), mediaType: "text", filename: "Résumé\nQ1.pdf", providerOptions: ["amazonBedrock": ["citations": .object(["enabled": .bool(true)])]])),
            .file(.init(data: .data(Data([137, 80, 78, 71])), mediaType: "image/png", providerOptions: ["bedrock": ["guardContent": .bool(true)]]))
        ], providerOptions: nil)]))
        let content = try await server.requestBody()["messages"]?.array.first?["content"]?.array ?? []
        #expect(content[0] == .object(["guardContent": .object(["text": .object(["text": .string("ground"), "qualifiers": .array([.string("grounding_source")])])])]))
        #expect(content[1]["video"]?["source"] == .object(["s3Location": .object(["uri": .string("s3://bucket/clip.mp4")])]))
        #expect(content[2]["document"]?["format"] == .string("txt"))
        #expect(content[2]["document"]?["name"] == .string("Rsum Q1"))
        #expect(content[2]["document"]?["source"] == .object(["bytes": .string(Data("document body".utf8).base64EncodedString())]))
        #expect(content[2]["document"]?["citations"] == .object(["enabled": .bool(true)]))
        #expect(content[3]["guardContent"]?["image"]?["format"] == .string("png"))
    }
}
