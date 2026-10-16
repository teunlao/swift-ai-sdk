import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AmazonBedrockProvider

@Suite("Bedrock provider boundaries")
struct BedrockProviderTests {
    @Test("Regional endpoints use the AWS partition", arguments: [
        ("cn-north-1", "amazonaws.com.cn"), ("us-iso-east-1", "c2s.ic.gov"),
        ("us-isob-east-1", "sc2s.sgov.gov"), ("eu-isoe-west-1", "cloud.adc-e.uk"),
        ("us-isof-south-1", "csp.hci.ic.gov"), ("eusc-de-east-1", "amazonaws.eu"), ("us-west-2", "amazonaws.com")
    ])
    func partitions(_ region: String, _ suffix: String) async throws {
        let server = try BedrockTestServer()
        _ = try await server.provider(region: region, baseURL: nil).chat(modelId: "model").doGenerate(options: .init(prompt: []))
        #expect(try await server.request().url?.host == "bedrock-runtime.\(region).\(suffix)")
    }

    @Test("Region validation is lazy, and explicit endpoints bypass hostname generation")
    func lazyRegion() async throws {
        let server = try BedrockTestServer()
        let invalid = server.provider(region: "bad.example/path", baseURL: nil).chat(modelId: "model")
        await #expect(throws: InvalidArgumentError.self) { _ = try await invalid.doGenerate(options: .init(prompt: [])) }
        let custom = server.provider(region: "bad.example/path", baseURL: "https://custom.test/").chat(modelId: "model")
        _ = try await custom.doGenerate(options: .init(prompt: []))
        #expect(try await server.request().url?.absoluteString == "https://custom.test/model/model/converse")
    }

    @Test("Absent region fails at request time instead of using a regional default")
    func missingRegion() async throws {
        let server = try BedrockTestServer()
        let model = server.provider(region: nil, baseURL: nil).chat(modelId: "model")
        if ProcessInfo.processInfo.environment["AWS_REGION"] == nil,
           ProcessInfo.processInfo.environment["AWS_ENDPOINT_URL_BEDROCK_RUNTIME"] == nil,
           ProcessInfo.processInfo.environment["AWS_ENDPOINT_URL"] == nil {
            await #expect(throws: LoadSettingError.self) { _ = try await model.doGenerate(options: .init(prompt: [])) }
        } else {
            _ = try await model.doGenerate(options: .init(prompt: []))
            #expect(try await server.request().url?.path == "/model/model/converse")
        }
    }

    @Test("Bearer authentication trims the key and uses the Bedrock user agent")
    func bearerHeaders() async throws {
        let server = try BedrockTestServer()
        let provider = createAmazonBedrock(settings: .init(apiKey: "  token  ", baseURL: "https://bedrock.test", headers: ["x-custom": "configured"], fetch: server.fetch))
        _ = try await provider.chat(modelId: "model").doGenerate(options: .init(prompt: [], headers: ["authorization": "old", "x-custom": "override"]))
        let request = try await server.request()
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "x-custom") == "override")
        #expect(request.value(forHTTPHeaderField: "user-agent")?.contains("ai-sdk-amazon-bedrock/") == true)
    }

    @Test("Reranking serializes JSON documents, paging and additional request fields")
    func reranking() async throws {
        let server = try BedrockTestServer(json: .object(["results": .array([.object(["index": .number(1), "relevanceScore": .number(0.8)])]), "nextToken": .string("next")]))
        let model = server.provider().reranking(modelId: .amazonRerankV1_0)
        let result = try await model.doRerank(options: .init(documents: .object(values: [["text": .string("first")], ["text": .string("second")]]), query: "query", topN: 1, providerOptions: ["amazonBedrock": ["nextToken": .string("page"), "additionalModelRequestFields": .object(["key": .number(1)])]]))
        #expect(result.ranking == [.init(index: 1, relevanceScore: 0.8)])
        let body = try await server.requestBody()
        #expect(body["nextToken"] == .string("page"))
        #expect(body["rerankingConfiguration"]?["bedrockRerankingConfiguration"]?["modelConfiguration"] == .object(["modelArn": .string("arn:aws:bedrock:us-east-1::foundation-model/amazon.rerank-v1:0"), "additionalModelRequestFields": .object(["key": .number(1)])]))
        #expect(body["sources"]?.array.last?["inlineDocumentSource"] == .object(["type": .string("JSON"), "jsonDocument": .object(["text": .string("second")])]))
        #expect(try await server.request().url?.path == "/rerank")
    }

    @Test("HTTP service errors preserve status and Bedrock error type")
    func httpError() async throws {
        let server = try BedrockTestServer(json: .object(["type": .string("ThrottlingException"), "message": .string("slow down")]), status: 429)
        do { _ = try await server.provider().embedding(modelId: .amazonTitanEmbedTextV2).doEmbed(options: .init(values: ["a"])); Issue.record("Expected API error") }
        catch let error as APICallError {
            #expect(error.statusCode == 429)
            #expect(error.isRetryable == true)
            #expect(error.message == "ThrottlingException: slow down")
        }
    }
}

@Suite("Bedrock native API subpaths")
struct BedrockSubpathTests {
    @Test("Anthropic Invoke transforms versioned tools and request betas")
    func anthropicInvoke() async throws {
        let response = Data(#"{"type":"message","id":"msg","model":"anthropic.claude-opus-4-6-v1","content":[{"type":"text","text":"answer"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":2}}"#.utf8)
        let server = BedrockTestServer(data: response)
        let provider = createAmazonBedrockAnthropic(settings: .init(apiKey: "token", baseURL: "https://custom.test/", headersProvider: { ["x-dynamic": "value", "user-agent": "custom-client", "anthropic-beta": "custom-beta"] }, fetch: server.fetch))
        let result = try await provider.messages(modelId: "anthropic.claude-opus-4-6-v1").doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: "anthropic.bash_20241022", name: "bash", args: [:]))], toolChoice: .auto))
        #expect(result.content == [.text(.init(text: "answer"))])
        let body = try await server.requestBody()
        #expect(body["model"] == nil)
        #expect(body["anthropic_version"] == .string("bedrock-2023-05-31"))
        #expect(body["tools"]?.array.first?["type"] == .string("bash_20250124"))
        #expect(body["anthropic_beta"]?.array.contains(.string("computer-use-2025-01-24")) == true)
        #expect(body["anthropic_beta"]?.array.contains(.string("custom-beta")) == true)
        #expect(try await server.request().value(forHTTPHeaderField: "user-agent")?.contains("custom-client") == true)
        #expect(try await server.request().url?.path == "/model/anthropic.claude-opus-4-6-v1/invoke")
        #expect(try await server.request().value(forHTTPHeaderField: "x-dynamic") == "value")
    }

    @Test("Anthropic Bedrock event frames are decoded into native model output")
    func anthropicEventStream() async throws {
        let events = [
            #"{"type":"message_start","message":{"id":"msg","type":"message","role":"assistant","model":"claude-3-haiku","content":[],"usage":{"input_tokens":1,"output_tokens":0}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"streamed"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}"#,
            #"{"type":"message_stop"}"#
        ]
        let frames = try events.map { try BedrockTestEventStream.jsonMessage(eventType: "chunk", payload: ["bytes": Data($0.utf8).base64EncodedString()]) }
        let server = BedrockTestServer(data: frames.reduce(into: Data()) { $0.append($1) }, headers: ["content-type": "application/vnd.amazon.eventstream"])
        let model = createAmazonBedrockAnthropic(settings: .init(apiKey: "token", baseURL: "https://bedrock.test", fetch: server.fetch)).messages(modelId: "anthropic.claude-3-haiku")
        let result = try await model.doStream(options: .init(prompt: []))
        let parts = try await convertReadableStreamToArray(result.stream)
        #expect(parts.contains(.textDelta(id: "0", delta: "streamed", providerMetadata: nil)))
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Expected finish"); return }
        #expect(reason.unified == .stop)
        #expect(usage.outputTokens.total == 2)
    }

    @Test("Mantle chooses its OpenAI route lazily", arguments: [("openai.gpt-oss-20b", "v1"), ("openai.gpt-5", "openai/v1"), ("google.gemma-4", "openai/v1"), ("xai.grok-4", "openai/v1")])
    func mantleRoute(_ id: String, _ route: String) async throws {
        let response = Data(#"{"id":"chat","model":"model","created":1,"choices":[{"index":0,"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#.utf8)
        let server = BedrockTestServer(data: response)
        let provider = createBedrockMantle(settings: .init(region: "us-west-2", apiKey: "token", fetch: server.fetch))
        let result = try await provider.chat(modelId: .init(rawValue: id)).doGenerate(options: .init(prompt: []))
        #expect(result.content == [.text(.init(text: "answer"))])
        #expect(try await server.request().url?.absoluteString == "https://bedrock-mantle.us-west-2.api.aws/\(route)/chat/completions")
    }

    @Test("Mantle Responses omits unsupported automatic web search source include")
    func mantleResponses() async throws {
        let server = BedrockTestServer(data: Data(#"{"id":"response","object":"response","created_at":1,"model":"model","status":"completed","output":[],"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#.utf8))
        let model = createBedrockMantle(settings: .init(apiKey: "token", baseURL: "https://custom.test/v1/", fetch: server.fetch)).responses(modelId: .gptOss20b)
        let result = try await model.doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: "openai.web_search", name: "search", args: [:]))]))
        #expect(result.usage.inputTokens.total == 1)
        #expect(try await server.requestBody()["include"]?.array.contains(.string("web_search_call.action.sources")) != true)
        #expect(try await server.request().url?.absoluteString == "https://custom.test/v1/responses")
    }
}
