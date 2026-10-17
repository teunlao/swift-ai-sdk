import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewaySpeechModel: SpeechModelV4 {
    public let modelId: String
    private let config: GatewayModelConfig
    public var provider: String { config.provider }

    init(modelId: String, config: GatewayModelConfig) {
        self.modelId = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let body = GatewaySpeechRequest(
            text: options.text,
            voice: options.voice?.nilIfEmpty,
            outputFormat: options.outputFormat?.nilIfEmpty,
            instructions: options.instructions?.nilIfEmpty,
            speed: options.speed,
            language: options.language?.nilIfEmpty,
            providerOptions: options.providerOptions
        )
        let result = try await config.post(
            "speech", modelId: modelId, body: gatewayJSON(body), headers: options.headers,
            abortSignal: options.abortSignal, response: GatewaySpeechResponse.self
        )
        return .init(
            audio: .base64(result.value.audio), warnings: result.value.warnings ?? [], usage: result.value.usage,
            response: .init(timestamp: Date(), modelId: modelId, headers: result.responseHeaders, body: result.rawValue),
            providerMetadata: result.value.providerMetadata
        )
    }
}

private struct GatewaySpeechRequest: Encodable {
    let text: String
    let voice: String?
    let outputFormat: String?
    let instructions: String?
    let speed: Double?
    let language: String?
    let providerOptions: SharedV4ProviderOptions?
}

private struct GatewaySpeechResponse: Decodable, Sendable {
    let audio: String
    let warnings: [SharedV4Warning]?
    let usage: JSONObject?
    let providerMetadata: SharedV4ProviderMetadata?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
