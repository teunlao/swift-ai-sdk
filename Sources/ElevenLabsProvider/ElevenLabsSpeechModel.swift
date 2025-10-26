import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/elevenlabs/src/elevenlabs-speech-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class ElevenLabsSpeechModel: SpeechModelV3 {
    private let modelIdentifier: ElevenLabsSpeechModelId
    private let config: ElevenLabsConfig

    public init(modelId: ElevenLabsSpeechModelId, config: ElevenLabsConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let prepared = try await prepareRequest(options: options)
        let now = config.currentDate()

        var url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/v1/text-to-speech/\(prepared.voiceId)"))
        if !prepared.queryItems.isEmpty {
            if var components = URLComponents(string: url) {
                components.queryItems = prepared.queryItems
                url = components.url?.absoluteString ?? url
            } else {
                let queryString = prepared.queryItems
                    .compactMap { item -> String? in
                        guard let value = item.value else { return nil }
                        return "\(item.name)=\(value)"
                    }
                    .joined(separator: "&")
                if !queryString.isEmpty {
                    url += "?\(queryString)"
                }
            }
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let requestBody = JSONValue.object(prepared.body)

        let response = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: requestBody,
            failedResponseHandler: elevenLabsFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let requestBodyString: String? = {
            let foundation = jsonValueToFoundation(requestBody)
            guard JSONSerialization.isValidJSONObject(foundation),
                  let data = try? JSONSerialization.data(withJSONObject: foundation) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }()

        return SpeechModelV3Result(
            audio: .binary(response.value),
            warnings: prepared.warnings,
            request: .init(body: requestBodyString),
            response: .init(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }

    // MARK: - Preparation

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let queryItems: [URLQueryItem]
        let warnings: [SpeechModelV3CallWarning]
        let voiceId: ElevenLabsSpeechVoiceId
    }

    private func prepareRequest(options: SpeechModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SpeechModelV3CallWarning] = []

        let providerOptions = try await parseProviderOptions(
            provider: "elevenlabs",
            providerOptions: options.providerOptions,
            schema: elevenLabsSpeechOptionsSchema
        )

        let voiceId: ElevenLabsSpeechVoiceId = options.voice ?? "21m00Tcm4TlvDq8ikWAM"

        var body: [String: JSONValue] = [
            "text": .string(options.text),
            "model_id": .string(modelIdentifier.rawValue)
        ]

        if let language = options.language, !language.isEmpty {
            body["language_code"] = .string(language)
        }

        var voiceSettings: [String: JSONValue] = [:]
        if let speed = options.speed {
            voiceSettings["speed"] = .number(speed)
        }

        if let providerOptions {
            if let settings = providerOptions.voiceSettings {
                if let stability = settings.stability {
                    voiceSettings["stability"] = .number(stability)
                }
                if let similarity = settings.similarityBoost {
                    voiceSettings["similarity_boost"] = .number(similarity)
                }
                if let style = settings.style {
                    voiceSettings["style"] = .number(style)
                }
                if let boost = settings.useSpeakerBoost {
                    voiceSettings["use_speaker_boost"] = .bool(boost)
                }
            }

            if body["language_code"] == nil, let languageCode = providerOptions.languageCode {
                body["language_code"] = .string(languageCode)
            }

            if let locators = providerOptions.pronunciationDictionaryLocators, !locators.isEmpty {
                let payload = locators.map { locator -> JSONValue in
                    var entry: [String: JSONValue] = [
                        "pronunciation_dictionary_id": .string(locator.pronunciationDictionaryId)
                    ]
                    if let version = locator.versionId {
                        entry["version_id"] = .string(version)
                    }
                    return .object(entry)
                }
                body["pronunciation_dictionary_locators"] = .array(payload)
            }

            if let seed = providerOptions.seed {
                body["seed"] = .number(Double(seed))
            }
            if let previousText = providerOptions.previousText {
                body["previous_text"] = .string(previousText)
            }
            if let nextText = providerOptions.nextText {
                body["next_text"] = .string(nextText)
            }
            if let previousIds = providerOptions.previousRequestIds, !previousIds.isEmpty {
                body["previous_request_ids"] = .array(previousIds.map(JSONValue.string))
            }
            if let nextIds = providerOptions.nextRequestIds, !nextIds.isEmpty {
                body["next_request_ids"] = .array(nextIds.map(JSONValue.string))
            }
            if let normalization = providerOptions.applyTextNormalization {
                body["apply_text_normalization"] = .string(normalization.rawValue)
            }
            if let languageNormalization = providerOptions.applyLanguageTextNormalization {
                body["apply_language_text_normalization"] = .bool(languageNormalization)
            }
        }

        if !voiceSettings.isEmpty {
            body["voice_settings"] = .object(voiceSettings)
        }

        if let instructions = options.instructions, !instructions.isEmpty {
            warnings.append(.unsupportedSetting(setting: "instructions", details: "ElevenLabs speech models do not support instructions. The instructions parameter was ignored."))
        }

        var queryItems: [URLQueryItem] = []
        if let outputFormat = options.outputFormat {
            let formatMap: [String: String] = [
                "mp3": "mp3_44100_128",
                "mp3_32": "mp3_44100_32",
                "mp3_64": "mp3_44100_64",
                "mp3_96": "mp3_44100_96",
                "mp3_128": "mp3_44100_128",
                "mp3_192": "mp3_44100_192",
                "pcm": "pcm_44100",
                "pcm_16000": "pcm_16000",
                "pcm_22050": "pcm_22050",
                "pcm_24000": "pcm_24000",
                "pcm_44100": "pcm_44100",
                "ulaw": "ulaw_8000"
            ]
            let mapped = formatMap[outputFormat] ?? outputFormat
            queryItems.append(URLQueryItem(name: "output_format", value: mapped))
        }

        if let providerOptions, let enableLogging = providerOptions.enableLogging {
            queryItems.append(URLQueryItem(name: "enable_logging", value: String(enableLogging)))
        }

        return PreparedRequest(
            body: body,
            queryItems: queryItems,
            warnings: warnings,
            voiceId: voiceId
        )
    }
}
