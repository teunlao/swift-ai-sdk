import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-speech-model.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

public final class FalSpeechModel: SpeechModelV4 {
    public var specificationVersion: String { "v4" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: FalSpeechModelId
    private let config: FalConfig

    init(modelId: FalSpeechModelId, config: FalConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let now = config.currentDate()
        let prepared = try await prepareRequest(options: options)

        let requestURL = config.url(.init(modelId: modelId, path: "https://fal.run/\(modelId)"))
        let response = try await postJsonToAPI(
            url: requestURL,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: falFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falSpeechResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let audioURL = response.value.audio.url
        let audioData = try await downloadAudio(
            url: audioURL,
            trustedOrigin: requestURL,
            abortSignal: options.abortSignal
        )

        return SpeechModelV4Result(
            audio: .binary(audioData),
            warnings: prepared.warnings,
            request: SpeechModelV4Result.RequestInfo(body: prepared.requestBodyString),
            response: SpeechModelV4Result.ResponseInfo(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            providerMetadata: nil
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
        let requestBodyString: String?
    }

    private func prepareRequest(options: SpeechModelV4CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        let falOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falSpeechModelOptionsSchema
        )

        var body: [String: JSONValue] = [
            "text": .string(options.text),
            "output_format": .string(options.outputFormat == "hex" ? "hex" : "url")
        ]

        if let voice = options.voice {
            body["voice"] = .string(voice)
        }
        if let speed = options.speed {
            body["speed"] = .number(speed)
        }

        if let language = options.language, !language.isEmpty {
            warnings.append(.unsupported(
                feature: "language",
                details: "fal speech models don't support 'language' directly; consider providerOptions.fal.language_boost"
            ))
        }

        if let output = options.outputFormat, !output.isEmpty, output != "url", output != "hex" {
            warnings.append(.unsupported(
                feature: "outputFormat",
                details: "Unsupported outputFormat: \(output). Using 'url' instead."
            ))
        }

        if let falOptions {
            // Merge after base keys so provider options can override them (matches upstream spread order).
            for (key, value) in falOptions.options {
                body[key] = value
            }
        }

        let requestBodyString = encodeJSONString(from: body)

        return PreparedRequest(body: body, warnings: warnings, requestBodyString: requestBodyString)
    }

    private func downloadAudio(url: String, trustedOrigin: String, abortSignal: (@Sendable () -> Bool)?) async throws -> Data {
        // The audio URL comes from the response body and may point at a foreign host: send no credentials.
        let result = try await getFromAPI(
            url: url,
            headers: nil,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: abortSignal,
            fetch: config.fetch,
            validateUrl: true,
            trustedOrigin: trustedOrigin
        )
        return result.value
    }
}

private struct FalSpeechResponse: Codable, Sendable {
    struct Audio: Codable, Sendable {
        let url: String
    }

    let audio: Audio
    let durationMs: Double?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case audio
        case durationMs = "duration_ms"
        case requestId = "request_id"
    }
}

private let falSpeechResponseSchema = FlexibleSchema(
    Schema<FalSpeechResponse>.codable(
        FalSpeechResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private func encodeJSONString(from dictionary: [String: JSONValue]) -> String? {
    var foundation: [String: Any] = [:]
    for (key, value) in dictionary {
        foundation[key] = jsonValueToFoundation(value)
    }
    guard JSONSerialization.isValidJSONObject(foundation) else {
        return nil
    }
    guard let data = try? JSONSerialization.data(withJSONObject: foundation, options: [.sortedKeys]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}
