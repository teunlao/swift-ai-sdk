import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-speech-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class FalSpeechModel: SpeechModelV3 {
    public var specificationVersion: String { "v3" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: FalSpeechModelId
    private let config: FalConfig

    init(modelId: FalSpeechModelId, config: FalConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let prepared = try await prepareRequest(options: options)
        let now = config.currentDate()

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "https://fal.run/\(modelIdentifier.rawValue)")),
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: falFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falSpeechResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let audioURL = response.value.audio.url
        let audioData = try await downloadAudio(url: audioURL, abortSignal: options.abortSignal)

        return SpeechModelV3Result(
            audio: .binary(audioData),
            warnings: prepared.warnings,
            request: SpeechModelV3Result.RequestInfo(body: prepared.requestBodyString),
            response: SpeechModelV3Result.ResponseInfo(
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
        let warnings: [SpeechModelV3CallWarning]
        let requestBodyString: String?
    }

    private func prepareRequest(options: SpeechModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SpeechModelV3CallWarning] = []

        let falOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falSpeechOptionsSchema
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

        if options.language != nil {
            warnings.append(.unsupportedSetting(setting: "language", details: "fal speech models do not support 'language'; use providerOptions.fal.language_boost instead."))
        }

        if let output = options.outputFormat, output != "url", output != "hex" {
            warnings.append(.unsupportedSetting(setting: "outputFormat", details: "Unsupported or unhandled outputFormat: \(output). Using 'url' instead."))
        }

        if let falOptions {
            if let voiceSettings = falOptions.voiceSetting {
                var payload: [String: JSONValue] = [:]
                if let speed = voiceSettings.speed { payload["speed"] = .number(speed) }
                if let vol = voiceSettings.vol { payload["vol"] = .number(vol) }
                if let voiceId = voiceSettings.voiceId { payload["voice_id"] = .string(voiceId) }
                if let pitch = voiceSettings.pitch { payload["pitch"] = .number(pitch) }
                if let englishNormalization = voiceSettings.englishNormalization { payload["english_normalization"] = .bool(englishNormalization) }
                if let emotion = voiceSettings.emotion { payload["emotion"] = .string(emotion) }
                if !payload.isEmpty {
                    body["voice_setting"] = .object(payload)
                }
            }

            if let audioSetting = falOptions.audioSetting, !audioSetting.isEmpty {
                body["audio_setting"] = .object(audioSetting)
            }

            if let boost = falOptions.languageBoost {
                body["language_boost"] = .string(boost)
            }

            if let pronunciation = falOptions.pronunciationDict, !pronunciation.isEmpty {
                body["pronunciation_dict"] = .object(pronunciation.mapValues(JSONValue.string))
            }
        }

        let requestBodyString = encodeJSONString(from: body)

        return PreparedRequest(body: body, warnings: warnings, requestBodyString: requestBodyString)
    }

    private func downloadAudio(url: String, abortSignal: (@Sendable () -> Bool)?) async throws -> Data {
        let result = try await getFromAPI(
            url: url,
            headers: nil,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: abortSignal,
            fetch: config.fetch
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
