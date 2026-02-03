import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/hume/src/hume-speech-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private let defaultVoiceIdentifier = "d8ab67c6-953d-4bd8-9370-8fa53a0f1453"

private struct HumeSpeechCallOptions: Codable, Sendable {
    struct Context: Codable, Sendable {
        struct Utterance: Codable, Sendable {
            struct Voice: Codable, Sendable {
                let id: String?
                let name: String?
                let provider: String?

                private enum CodingKeys: String, CodingKey { case id, name, provider }

                init(id: String? = nil, name: String? = nil, provider: String? = nil) {
                    self.id = id
                    self.name = name
                    self.provider = provider
                }
            }

            let text: String
            let description: String?
            let speed: Double?
            let trailingSilence: Double?
            let voice: Voice?

            private enum CodingKeys: String, CodingKey {
                case text
                case description
                case speed
                case trailingSilence
                case voice
            }
        }

        let generationId: String?
        let utterances: [Utterance]?

        private enum CodingKeys: String, CodingKey {
            case generationId
            case utterances
        }
    }

    let context: Context?
}

private let humeSpeechCallOptionsSchema = FlexibleSchema(
    Schema<HumeSpeechCallOptions>.codable(
        HumeSpeechCallOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

struct HumeSpeechModelConfig: Sendable {
    let provider: String
    let url: @Sendable (_ options: (modelId: String, path: String)) -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        config: HumeConfig,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = config.provider
        self.url = config.url
        self.headers = config.headers
        self.fetch = config.fetch
        self.currentDate = currentDate
    }
}

public final class HumeSpeechModel: SpeechModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier }

    private let modelIdentifier: String
    private let config: HumeSpeechModelConfig

    init(modelId: String, config: HumeSpeechModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let now = config.currentDate()

        var warnings: [SharedV3Warning] = []

        // Parse provider-specific options
        let providerOptions = try await parseProviderOptions(
            provider: "hume",
            providerOptions: options.providerOptions,
            schema: humeSpeechCallOptionsSchema
        )

        // Build default request body
        var requestBody = HumeSpeechAPITypes(
            utterances: [
                HumeSpeechAPIUtterance(
                    text: options.text,
                    description: options.instructions,
                    speed: options.speed,
                    trailingSilence: nil,
                    voice: HumeSpeechAPIVoice(
                        id: options.voice ?? defaultVoiceIdentifier,
                        name: nil,
                        provider: "HUME_AI"
                    )
                )
            ],
            context: nil,
            format: .init(type: "mp3")
        )

        if let outputFormat = options.outputFormat {
            if ["mp3", "pcm", "wav"].contains(outputFormat) {
                requestBody.format = .init(type: outputFormat)
            } else {
                warnings.append(
                    .unsupported(
                        feature: "outputFormat",
                        details: "Unsupported output format: \(outputFormat). Using mp3 instead."
                    )
                )
            }
        }

        if let language = options.language {
            warnings.append(
                .unsupported(
                    feature: "language",
                    details: "Hume speech models do not support language selection. Language parameter \"\(language)\" was ignored."
                )
            )
        }

        if let humeOptions = providerOptions, let context = humeOptions.context {
            if let generationId = context.generationId {
                requestBody.context = HumeSpeechAPIContext(
                    generationID: generationId,
                    utterances: nil
                )
            } else if let utterances = context.utterances {
                let mapped = utterances.map { utterance -> HumeSpeechAPIUtterance in
                    let voice: HumeSpeechAPIVoice?
                    if let optionVoice = utterance.voice {
                        voice = HumeSpeechAPIVoice(
                            id: optionVoice.id,
                            name: optionVoice.name,
                            provider: optionVoice.provider
                        )
                    } else {
                        voice = nil
                    }

                    return HumeSpeechAPIUtterance(
                        text: utterance.text,
                        description: utterance.description,
                        speed: utterance.speed,
                        trailingSilence: utterance.trailingSilence,
                        voice: voice
                    )
                }

                requestBody.context = HumeSpeechAPIContext(
                    generationID: nil,
                    utterances: mapped
                )
            }
        }

        let headers = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url((modelId: modelIdentifier, path: "/v0/tts/file")),
            headers: headers,
            body: requestBody,
            failedResponseHandler: humeFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let requestBodyString: String? = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            guard let data = try? encoder.encode(requestBody) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return SpeechModelV3Result(
            audio: .binary(response.value),
            warnings: warnings,
            request: SpeechModelV3Result.RequestInfo(body: requestBodyString),
            response: SpeechModelV3Result.ResponseInfo(
                timestamp: now,
                modelId: modelIdentifier,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}
