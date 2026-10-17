import Foundation
import Testing
import AISDKProvider
import GatewayProvider

@Suite("Gateway option and metadata codecs")
struct GatewayOptionsMetadataTests {
    @Test("Provider options encode routing controls and service-owned fields at the wire level")
    func providerOptionsRoundTrip() throws {
        let options = GatewayProviderOptions(
            models: ["anthropic/claude-sonnet-5.5"],
            byok: ["anthropic": [["apiKey": "request-key"]]],
            caching: .auto,
            disallowPromptTraining: true,
            has: ["vision", "!quantization:fp8"],
            providerTimeouts: .init(byok: ["anthropic": 2500]),
            quotaEntityId: "account-1",
            serviceTier: .priority,
            sort: .ttft,
            zeroDataRetention: false,
            additionalOptions: ["serviceFeature": .object(["enabled": .bool(true)]), "nullable": .null]
        )
        let data = try JSONEncoder().encode(options)
        let wire = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(wire == .object([
            "models": .array(["anthropic/claude-sonnet-5.5"]),
            "byok": .object(["anthropic": .array([.object(["apiKey": "request-key"])])]),
            "caching": "auto",
            "disallowPromptTraining": true,
            "has": .array(["vision", "!quantization:fp8"]),
            "providerTimeouts": .object(["byok": .object(["anthropic": 2500])]),
            "quotaEntityId": "account-1",
            "serviceTier": "priority",
            "sort": "ttft",
            "zeroDataRetention": false,
            "serviceFeature": .object(["enabled": true]),
            "nullable": .null,
        ]))
        #expect(try JSONDecoder().decode(GatewayProviderOptions.self, from: data) == options)
    }

    @Test("Async job metadata preserves the job and unknown service fields")
    func asyncJobMetadataRoundTrip() throws {
        let wire = #"{"asyncJob":{"jobId":"job_1","status":"queued","webhookSigningSecret":"secret","progress":null},"cost":"0.01"}"#
        let metadata = try JSONDecoder().decode(GatewayProviderMetadata.self, from: Data(wire.utf8))
        #expect(metadata.asyncJob?.jobId == "job_1")
        #expect(metadata.asyncJob?.status == "queued")
        #expect(metadata.asyncJob?.webhookSigningSecret == "secret")
        #expect(metadata.asyncJob?.additionalMetadata["progress"] == .null)
        #expect(metadata.additionalMetadata["cost"] == "0.01")
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(metadata))
            == JSONDecoder().decode(JSONValue.self, from: Data(wire.utf8)))
    }
}
