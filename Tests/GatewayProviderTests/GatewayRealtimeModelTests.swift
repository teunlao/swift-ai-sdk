import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("Gateway realtime")
struct GatewayRealtimeModelTests {
    @Test("realtime client secrets are minted at the API origin and use auth subprotocols")
    func clientSecret() async throws {
        let provider = createGateway(settings: .init(baseURL: "https://proxy.test/custom/v4/ai", apiKey: "gateway-key", teamIdOrSlug: "team / тест", fetch: { request in
            #expect(request.url?.absoluteString == "https://proxy.test/v1/realtime/client-secrets")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gateway-key")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["model"] as? String == "openai/gpt-realtime-2")
            #expect(body["expiresIn"] as? Int == 120)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return FetchResponse(body: .data(Data(#"{"token":"vcst_short","expiresAt":1234.125}"#.utf8)), urlResponse: response)
        }))
        let token = try await provider.experimental_realtime.getToken(options: .init(model: "openai/gpt-realtime-2", expiresAfterSeconds: 120))
        #expect(token.token == "vcst_short")
        #expect(token.expiresAt == 1234.125)
        #expect(token.url == "wss://proxy.test/custom/v4/ai/realtime-model?ai-model-id=openai%2Fgpt-realtime-2")
        let model = provider.experimental_realtime("openai/gpt-realtime-2")
        let connection = try model.getWebSocketConfig(options: .init(token: token.token, url: token.url))
        let protocols = try #require(connection.protocols)
        #expect(protocols.first == GATEWAY_REALTIME_SUBPROTOCOL)
        let header = " \(protocols.joined(separator: ", ")) "
        #expect(getGatewayRealtimeAuthToken(header) == "vcst_short")
        #expect(getGatewayRealtimeTeamIdOrSlug(header) == "team / тест")
    }

    @Test("normalized realtime events preserve event identity and provider raw data")
    func normalizedCodec() async throws {
        let model = createGateway().experimental_realtime("openai/gpt-realtime-2")
        let config = RealtimeModelV4SessionConfig(
            instructions: "Speak", inputAudioFormat: .init(type: "audio/pcm", rate: 24000),
            turnDetection: .serverVAD(threshold: 0.5, silenceDurationMs: 300, prefixPaddingMs: 100),
            providerOptions: ["vendor": .object(["flag": .bool(true)])]
        )
        let payload = try await model.serializeClientEvent(.sessionUpdate(config: config, eventId: "evt_1"))
        guard case .some(.object(let body)) = payload, case .object(let session)? = body["config"] else {
            Issue.record("Expected normalized session update")
            return
        }
        #expect(body["type"] == .string("session-update"))
        #expect(body["eventId"] == .string("evt_1"))
        #expect(session["inputAudioFormat"] == .object(["type": "audio/pcm", "rate": 24000]))
        #expect(session["turnDetection"] == .object(["type": "server-vad", "threshold": 0.5, "silenceDurationMs": 300, "prefixPaddingMs": 100]))
        #expect(session["providerOptions"] == .object(["vendor": .object(["flag": .bool(true)])]))
        let raw: JSONValue = ["opaque": "provider-data"]
        let events = try model.parseServerEvent(raw: ["type": "function-call-arguments-done", "responseId": "response", "itemId": "item", "callId": "call", "name": "weather", "arguments": "{}", "raw": raw])
        #expect(events == [.functionCallArgumentsDone(responseId: "response", itemId: "item", callId: "call", name: "weather", arguments: "{}", raw: raw)])
        let context = try await model.serializeClientEvent(.contextAppend(content: "state", delegationId: nil, eventId: "event", providerOptions: nil))
        #expect(context == .object(["type": "context-append", "content": "state", "delegationId": .null, "eventId": "event"]))
    }
}
