import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

@Suite("Azure-hosted DeepSeek")
struct AzureDeepSeekTests {
    @Test("Azure accepts penalties, sampling, and native JSON schema without a thinking control")
    func deploymentCapabilities() async throws {
        let capture = Capture()
        let provider = try createAzure(settings: .init(
            resourceName: "resource",
            apiKey: "azure-key",
            fetch: capture.fetch,
            apiVersion: "2025-04-01-preview",
            useDeploymentBasedUrls: true
        ))
        let settings = AzureDeepSeekLanguageModelOptions(
            topLogprobs: 2,
            userId: "tenant_1",
            reasoningEffort: .low,
            strictJsonSchema: false
        )
        var azureOptions = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(settings))
        azureOptions["thinking"] = ["type": "enabled"]
        let schema: JSONValue = ["type": "object", "properties": ["answer": ["type": "integer"]]]
        let result = try await provider.deepseek("reasoning-deployment").doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Find the answer."))], providerOptions: nil)],
            temperature: 0.6,
            topP: 0.9,
            presencePenalty: -0.25,
            frequencyPenalty: 0.4,
            responseFormat: .json(schema: schema, name: "Answer", description: "An answer"),
            reasoning: .high,
            providerOptions: ["azure": azureOptions, "deepseek": ["userId": "wrong_namespace", "strictJsonSchema": true]]
        ))

        let request = try #require(await capture.requests.first)
        let data = try #require(request.httpBody)
        let body = try JSONDecoder().decode(JSONObject.self, from: data)
        #expect(request.url?.absoluteString == "https://resource.openai.azure.com/openai/deployments/reasoning-deployment/chat/completions?api-version=2025-04-01-preview")
        #expect(request.value(forHTTPHeaderField: "api-key") == "azure-key")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-azure/") == true)
        #expect(body["model"] == "reasoning-deployment")
        #expect(body["temperature"] == 0.6)
        #expect(body["top_p"] == 0.9)
        #expect(body["presence_penalty"] == -0.25)
        #expect(body["frequency_penalty"] == 0.4)
        #expect(body["thinking"] == nil)
        #expect(body["reasoning_effort"] == "low")
        #expect(body["user_id"] == "tenant_1")
        #expect(body["logprobs"] == true)
        #expect(body["top_logprobs"] == 2)
        #expect(body["response_format"] == [
            "type": "json_schema",
            "json_schema": ["schema": schema, "strict": false, "name": "Answer", "description": "An answer"]
        ])
        let messagesValue = try #require(body["messages"])
        guard case .array(let messages) = messagesValue else {
            Issue.record("Expected messages array.")
            return
        }
        #expect(messages.count == 1)
        #expect(result.warnings.isEmpty)
        #expect(result.content == [.reasoning(.init(text: "Check")), .text(.init(text: #"{"answer":42}"#))])
        #expect(result.providerMetadata?["azure"] == [
            "promptCacheHitTokens": 4,
            "promptCacheMissTokens": 6,
            "responseObject": "chat.completion",
            "choiceIndex": 0,
            "messageRole": "assistant"
        ])
    }

    @Test("Custom gateway and Entra authentication use the Azure request boundary")
    func gatewayAuthentication() async throws {
        let capture = Capture()
        let provider = try createAzure(settings: .init(
            baseURL: "https://gateway.example.com/azure/",
            tokenProvider: { "entra-token" },
            headers: ["X-Provider": "provider"],
            fetch: capture.fetch
        ))
        let model = provider.deepseek("deployment")
        _ = try await model.doGenerate(options: .init(prompt: []))
        _ = try await model.doGenerate(options: .init(prompt: [], headers: ["aUtHoRiZaTiOn": "Bearer caller", "X-Request": "request"]))
        let requests = await capture.requests
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://gateway.example.com/azure/chat/completions",
            "https://gateway.example.com/azure/chat/completions"
        ])
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer entra-token", "Bearer caller"])
        let request = try #require(requests.last)
        #expect(request.value(forHTTPHeaderField: "api-key") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
        #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
    }

    private actor Capture {
        var requests: [URLRequest] = []
        nonisolated var fetch: FetchFunction {
            { request in try await self.respond(request) }
        }
        private func respond(_ request: URLRequest) throws -> FetchResponse {
            requests.append(request)
            let response: JSONValue = [
                "id": "result", "created": 0, "model": "reasoning-deployment", "object": "chat.completion",
                "choices": [["index": 0, "message": ["role": "assistant", "reasoning_content": "Check", "content": #"{"answer":42}"#], "finish_reason": "stop"]],
                "usage": ["prompt_tokens": 10, "completion_tokens": 3, "prompt_cache_hit_tokens": 4, "prompt_cache_miss_tokens": 6]
            ]
            return FetchResponse(
                body: .data(try JSONEncoder().encode(response)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }
    }
}
