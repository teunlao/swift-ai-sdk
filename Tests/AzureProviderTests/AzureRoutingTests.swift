import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

@Suite("Azure routing and authentication")
struct AzureRoutingTests {
    struct Route: Sendable {
        let baseURL: String
        let deployment: Bool
        let expectedURL: String
    }

    @Test("Azure endpoints and custom gateways own their routing and versioning", arguments: [
        Route(
            baseURL: "https://gateway.example.com/azure/",
            deployment: false,
            expectedURL: "https://gateway.example.com/azure/chat/completions"
        ),
        Route(
            baseURL: "https://resource.openai.azure.com/openai/v1/",
            deployment: false,
            expectedURL: "https://resource.openai.azure.com/openai/v1/chat/completions"
        ),
        Route(
            baseURL: "https://resource.services.ai.azure.com/api/projects/project/openai",
            deployment: false,
            expectedURL: "https://resource.services.ai.azure.com/api/projects/project/openai/v1/chat/completions"
        ),
        Route(
            baseURL: "https://resource.cognitiveservices.azure.com/openai",
            deployment: false,
            expectedURL: "https://resource.cognitiveservices.azure.com/openai/v1/chat/completions?api-version=2025-04-01-preview"
        ),
        Route(
            baseURL: "https://gateway.example.com/azure",
            deployment: true,
            expectedURL: "https://gateway.example.com/azure/deployments/deployment/chat/completions?api-version=2025-04-01-preview"
        ),
        Route(
            baseURL: "https://RESOURCE.OPENAI.AZURE.COM/OpenAI/V1",
            deployment: false,
            expectedURL: "https://resource.openai.azure.com/OpenAI/V1/chat/completions"
        )
    ])
    func requestRouting(route: Route) async throws {
        let capture = RequestCapture()
        let provider = try createAzure(settings: .init(
            resourceName: "ignored@invalid/#",
            baseURL: route.baseURL,
            apiKey: "key",
            fetch: capture.fetch,
            apiVersion: "2025-04-01-preview",
            useDeploymentBasedUrls: route.deployment
        ))

        let result = try await provider.chat("deployment").doGenerate(options: .init(prompt: [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]))
        let request = try #require(await capture.requests.first)
        #expect(request.url?.absoluteString == route.expectedURL)
        #expect(request.value(forHTTPHeaderField: "api-key") == "key")
        #expect(result.content == [.text(.init(text: "Hello from Azure", providerMetadata: nil))])
    }

    @Test("API version is serialized as a URLSearchParams value")
    func apiVersionEncoding() async throws {
        let capture = RequestCapture()
        let provider = try createAzure(settings: .init(
            resourceName: "resource",
            apiKey: "key",
            fetch: capture.fetch,
            apiVersion: "preview+test~ one"
        ))
        _ = try await provider.chat("deployment").doGenerate(options: .init(prompt: []))
        let request = try #require(await capture.requests.first)
        #expect(request.url?.absoluteString == "https://resource.openai.azure.com/openai/v1/chat/completions?api-version=preview%2Btest%7E+one")
    }

    @Test("Entra tokens resolve for each API request without an API key")
    func requestTimeTokens() async throws {
        actor TokenSource {
            var token = "unused"
            func set(_ value: String) { token = value }
            func current() -> String { token }
        }
        let tokens = TokenSource()
        let capture = RequestCapture()
        let provider = try createAzure(settings: .init(
            resourceName: "resource",
            tokenProvider: { await tokens.current() },
            headers: ["User-Agent": "application/1.0", "X-Provider": "provider"],
            fetch: capture.fetch
        ))
        let model = provider.chat("deployment")
        await tokens.set("first")
        _ = try await model.doGenerate(options: .init(prompt: []))
        await tokens.set("second")
        _ = try await model.doGenerate(options: .init(prompt: [], headers: ["X-Request": "request"]))

        let requests = await capture.requests
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer first", "Bearer second"])
        let request = try #require(requests.last)
        #expect(request.url?.absoluteString == "https://resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
        #expect(request.value(forHTTPHeaderField: "api-key") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
        #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("application/1.0") == true)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-azure/") == true)
    }

    @Test("Explicit Authorization overrides Entra token resolution", arguments: [true, false])
    func explicitAuthorization(providerHeader: Bool) async throws {
        enum UnexpectedTokenRequest: Error { case requested }
        let capture = RequestCapture()
        let provider = try createAzure(settings: .init(
            baseURL: "https://gateway.example.com/azure",
            tokenProvider: { throw UnexpectedTokenRequest.requested },
            headers: providerHeader ? ["Authorization": "Bearer application"] : nil,
            fetch: capture.fetch
        ))
        _ = try await provider.chat("deployment").doGenerate(options: .init(
            prompt: [],
            headers: providerHeader ? nil : ["aUtHoRiZaTiOn": "Bearer application"]
        ))
        let request = try #require(await capture.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer application")
        #expect(request.value(forHTTPHeaderField: "api-key") == nil)
    }

    @Test("Per-request API credentials override provider defaults")
    func apiKeyHeaders() async throws {
        let capture = RequestCapture()
        let provider = try createAzure(settings: .init(
            baseURL: "https://gateway.example.com/azure",
            apiKey: "configured-key",
            headers: ["API-KEY": "provider-key"],
            fetch: capture.fetch
        ))
        let model = provider.chat("deployment")
        _ = try await model.doGenerate(options: .init(prompt: []))
        _ = try await model.doGenerate(options: .init(prompt: [], headers: ["api-key": "request-key"]))
        let requests = await capture.requests
        #expect(requests.map { $0.value(forHTTPHeaderField: "api-key") } == ["provider-key", "request-key"])
    }

    @Test("Ambiguous authentication and invalid base URLs are rejected when configured")
    func invalidConfiguration() throws {
        #expect(throws: InvalidArgumentError.self) {
            try createAzure(settings: .init(apiKey: "key", tokenProvider: { "token" }))
        }
        #expect(throws: InvalidArgumentError.self) {
            try createAzureProvider(settings: .init(baseURL: "not an absolute URL", apiKey: "key"))
        }
    }

    @Test("Resource names cannot rewrite the API host", arguments: ["user@internal:8080/#", "-resource", "resource\n"])
    func invalidResourceName(resourceName: String) async throws {
        let capture = RequestCapture()
        let provider = try createAzure(settings: .init(resourceName: resourceName, apiKey: "key", fetch: capture.fetch))
        let model = provider.chat("deployment")
        do {
            _ = try await model.doGenerate(options: .init(prompt: []))
            Issue.record("An invalid resource name reached the API.")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "resourceName")
        }
    }

    @Test("image deployments retain unknown capabilities while using the native Image request")
    func imageCapabilities() async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/openai/v1/images/edits")
            #expect(request.value(forHTTPHeaderField: "api-key") == "key")
            return FetchResponse(body: .data(Data(#"{"data":[{"b64_json":"azure-image"}]}"#.utf8)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!)
        }))
        let model: any ImageModelV4 = provider.image("dall-e-2")
        #expect(try await model.supportsFileInputs == nil)
        #expect(try await model.supportsMaskInputs == nil)
        let result = try await model.doGenerate(options: .init(n: 1, files: []))
        #expect(result.images == .base64(["azure-image"]))
    }

    private actor RequestCapture {
        var requests: [URLRequest] = []

        nonisolated var fetch: FetchFunction {
            { request in try await self.respond(to: request) }
        }

        private func respond(to request: URLRequest) throws -> FetchResponse {
            requests.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(
                body: .data(Data(#"{"id":"chat","created":0,"model":"deployment","choices":[{"index":0,"message":{"role":"assistant","content":"Hello from Azure"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#.utf8)),
                urlResponse: response
            )
        }
    }
}
