import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private actor OpenAIRealtimeRequestCapture {
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }

    func first() -> URLRequest? {
        requests.first
    }
}

private func openAIRealtimeFetch(
    capture: OpenAIRealtimeRequestCapture,
    statusCode: Int = 200,
    body: @escaping @Sendable () -> [String: Any] = { ["value": "secret", "expires_at": 123] }
) -> FetchFunction {
    { request in
        await capture.append(request)
        let data = try JSONSerialization.data(withJSONObject: body())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return FetchResponse(body: .data(data), urlResponse: response)
    }
}

private func openAIRealtimeRequestJSON(_ request: URLRequest) throws -> JSONValue {
    guard let body = request.httpBody else {
        throw InvalidArgumentError(argument: "request.httpBody", message: "missing request body")
    }
    return try JSONDecoder().decode(JSONValue.self, from: body)
}

@Suite("OpenAI Realtime Model")
struct OpenAIRealtimeModelTests {
    @Test("provider exposes upstream experimental realtime factory")
    func providerExposesExperimentalRealtimeFactory() throws {
        let provider = try createOpenAIProvider(settings: .init(apiKey: "test-api-key", name: "custom-openai"))
        let model = provider.experimental_realtime.realtimeModel(modelId: "gpt-realtime")

        #expect(model.specificationVersion == "v4")
        #expect(model.provider == "custom-openai.realtime")
        #expect(model.modelId == "gpt-realtime")
    }

    @Test("getToken creates client secret without expires_after by default")
    func getTokenCreatesClientSecretWithoutExpiresAfterByDefault() async throws {
        let capture = OpenAIRealtimeRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            baseURL: "https://api.openai.com/v1",
            apiKey: "test-api-key",
            organization: "test-org",
            project: "test-project",
            headers: ["Custom-Header": "custom-value"],
            fetch: openAIRealtimeFetch(capture: capture)
        ))

        let token = try await provider.experimental_realtime.getToken(options: .init(model: "gpt-realtime"))

        #expect(token == .init(
            token: "secret",
            url: "wss://api.openai.com/v1/realtime?model=gpt-realtime",
            expiresAt: 123
        ))

        let request = try #require(await capture.first())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/realtime/client_secrets")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "test-org")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == "test-project")
        #expect(request.value(forHTTPHeaderField: "Custom-Header") == "custom-value")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        #expect(try openAIRealtimeRequestJSON(request) == [
            "session": [
                "type": "realtime",
                "model": "gpt-realtime"
            ]
        ])
    }

    @Test("client secret request includes expires_after anchor and session config")
    func clientSecretRequestIncludesExpiresAfterAnchorAndSessionConfig() async throws {
        let capture = OpenAIRealtimeRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIRealtimeFetch(capture: capture)
        ))

        let session = RealtimeModelV4SessionConfig(
            instructions: "Stay concise",
            voice: "alloy",
            outputModalities: [.text, .audio],
            inputAudioFormat: .init(type: "pcm16", rate: 24_000),
            inputAudioTranscription: .init(language: "en", prompt: "Product names"),
            outputAudioFormat: .init(type: "opus"),
            turnDetection: .semanticVAD(threshold: 0.5, silenceDurationMs: 600, prefixPaddingMs: 250),
            tools: [
                .init(
                    name: "lookup",
                    parameters: ["type": "object"],
                    description: "Lookup facts"
                )
            ],
            providerOptions: ["temperature": 0.7]
        )

        _ = try await provider.experimental_realtime.getToken(options: .init(
            model: "gpt-realtime",
            expiresAfterSeconds: 60,
            sessionConfig: session
        ))

        let request = try #require(await capture.first())
        #expect(try openAIRealtimeRequestJSON(request) == [
            "expires_after": [
                "anchor": "created_at",
                "seconds": 60
            ],
            "session": [
                "type": "realtime",
                "model": "gpt-realtime",
                "instructions": "Stay concise",
                "output_modalities": ["text", "audio"],
                "audio": [
                    "input": [
                        "format": ["type": "pcm16", "rate": 24_000],
                        "turn_detection": [
                            "type": "semantic_vad",
                            "threshold": 0.5,
                            "silence_duration_ms": 600,
                            "prefix_padding_ms": 250
                        ],
                        "transcription": [
                            "model": "gpt-realtime-whisper",
                            "language": "en",
                            "prompt": "Product names"
                        ]
                    ],
                    "output": [
                        "format": ["type": "opus"],
                        "voice": "alloy"
                    ]
                ],
                "tools": [
                    [
                        "type": "function",
                        "name": "lookup",
                        "description": "Lookup facts",
                        "parameters": ["type": "object"]
                    ]
                ],
                "tool_choice": "auto",
                "temperature": 0.7
            ]
        ])
    }

    @Test("websocket config uses OpenAI realtime subprotocols")
    func websocketConfigUsesOpenAIRealtimeSubprotocols() throws {
        let model = OpenAIRealtimeModel(
            modelId: "gpt-realtime",
            config: .init(
                provider: "openai.realtime",
                baseURL: "https://api.openai.com/v1",
                headers: { [:] }
            )
        )

        let config = try model.getWebSocketConfig(options: .init(
            token: "secret",
            url: "wss://api.openai.com/v1/realtime?model=gpt-realtime"
        ))

        #expect(config.url == "wss://api.openai.com/v1/realtime?model=gpt-realtime")
        #expect(config.protocols == ["realtime", "openai-insecure-api-key.secret"])
    }

    @Test("buildSessionConfig maps OpenAI realtime session shape")
    func buildSessionConfigMapsOpenAIRealtimeSessionShape() throws {
        let model = OpenAIRealtimeModel(
            modelId: "gpt-realtime",
            config: .init(provider: "openai.realtime", baseURL: "https://api.openai.com/v1", headers: { [:] })
        )

        #expect(try model.buildSessionConfig(.init(turnDetection: .disabled)) == [
            "type": "realtime",
            "model": "gpt-realtime",
            "audio": [
                "input": [
                    "turn_detection": nil
                ]
            ]
        ])
    }

    @Test("parseServerEvent maps OpenAI realtime server events")
    func parseServerEventMapsOpenAIRealtimeServerEvents() throws {
        let model = OpenAIRealtimeModel(
            modelId: "gpt-realtime",
            config: .init(provider: "openai.realtime", baseURL: "https://api.openai.com/v1", headers: { [:] })
        )

        let done: JSONValue = [
            "type": "response.done",
            "response": ["id": "resp-1", "status": "completed"]
        ]
        #expect(try model.parseServerEvent(raw: done) == [
            .responseDone(responseId: "resp-1", status: "completed", raw: done)
        ])

        let functionDone: JSONValue = [
            "type": "response.function_call_arguments.done",
            "response_id": "resp-1",
            "item_id": "item-1",
            "call_id": "call-1",
            "name": "lookup",
            "arguments": "{\"query\":\"swift\"}"
        ]
        #expect(try model.parseServerEvent(raw: functionDone) == [
            .functionCallArgumentsDone(
                responseId: "resp-1",
                itemId: "item-1",
                callId: "call-1",
                name: "lookup",
                arguments: "{\"query\":\"swift\"}",
                raw: functionDone
            )
        ])

        let error: JSONValue = [
            "type": "error",
            "error": ["message": "bad request", "code": "invalid_request"]
        ]
        #expect(try model.parseServerEvent(raw: error) == [
            .error(message: "bad request", code: "invalid_request", raw: error)
        ])

        let custom: JSONValue = ["type": "rate_limits.updated", "payload": true]
        #expect(try model.parseServerEvent(raw: custom) == [
            .custom(rawType: "rate_limits.updated", raw: custom)
        ])
    }

    @Test("serializeClientEvent maps OpenAI realtime client events")
    func serializeClientEventMapsOpenAIRealtimeClientEvents() async throws {
        let model = OpenAIRealtimeModel(
            modelId: "gpt-realtime",
            config: .init(provider: "openai.realtime", baseURL: "https://api.openai.com/v1", headers: { [:] })
        )

        #expect(try await model.serializeClientEvent(.responseCreate(options: .init(
            modalities: ["text", "audio"],
            instructions: "Answer",
            metadata: ["trace": "t-1"]
        ))) == [
            "type": "response.create",
            "response": [
                "output_modalities": ["text", "audio"],
                "instructions": "Answer",
                "metadata": ["trace": "t-1"]
            ]
        ])

        #expect(try await model.serializeClientEvent(.conversationItemCreate(item: .textMessage(text: "hello"))) == [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": "hello"]]
            ]
        ])

        #expect(try await model.serializeClientEvent(.conversationItemCreate(
            item: .functionCallOutput(callId: "call-1", name: "lookup", output: "{\"ok\":true}")
        )) == [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": "call-1",
                "output": "{\"ok\":true}"
            ]
        ])
    }
}
