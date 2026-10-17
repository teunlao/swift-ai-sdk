import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class MistralSpeechModel: SpeechModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        let currentDate: (@Sendable () -> Date)?

        init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
            fetch: FetchFunction? = nil,
            currentDate: (@Sendable () -> Date)? = nil
        ) {
            self.provider = provider
            self.baseURL = baseURL
            self.headers = headers
            self.fetch = fetch
            self.currentDate = currentDate
        }
    }

    private let modelIdentifier: MistralSpeechModelId
    private let config: Config

    init(modelId: MistralSpeechModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let timestamp = config.currentDate?() ?? Date()
        let mistralOptions = try await parseProviderOptions(
            provider: "mistral",
            providerOptions: options.providerOptions,
            schema: mistralSpeechModelOptionsSchema
        )
        var warnings: [SharedV4Warning] = []
        let requestedFormat = options.outputFormat ?? "mp3"
        let responseFormat: String
        if ["pcm", "wav", "mp3", "flac", "opus"].contains(requestedFormat) {
            responseFormat = requestedFormat
        } else {
            responseFormat = "mp3"
            warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(requestedFormat). Using mp3 instead."))
        }
        if options.instructions != nil {
            warnings.append(.unsupported(feature: "instructions", details: "Mistral speech models do not support the `instructions` option. Use a reference audio clip to guide delivery."))
        }
        if options.speed != nil {
            warnings.append(.unsupported(feature: "speed", details: "Mistral speech models do not support the `speed` option. It was ignored."))
        }
        if options.language != nil {
            warnings.append(.unsupported(feature: "language", details: "Mistral speech models do not support the `language` option. Language is inferred from the input text and voice."))
        }

        var body: JSONObject = [
            "model": .string(modelId),
            "input": .string(options.text),
            "response_format": .string(responseFormat),
            "stream": .bool(false)
        ]
        if let refAudio = mistralOptions?.refAudio {
            body["ref_audio"] = .string(refAudio)
        } else if let voice = options.voice {
            body["voice_id"] = .string(voice)
        }
        var requestBodyValues = body
        if mistralOptions?.refAudio != nil {
            requestBodyValues["ref_audio"] = .string("[redacted]")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let response = try await postToAPI(
            url: "\(config.baseURL)/audio/speech",
            headers: combineHeaders(
                ["Content-Type": "application/json"],
                try config.headers(),
                options.headers?.mapValues(Optional.some)
            ).compactMapValues { $0 },
            body: PostBody(content: .json(try encoder.encode(JSONValue.object(body))), values: requestBodyValues),
            failedResponseHandler: mistralFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mistralSpeechResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        return SpeechModelV4Result(
            audio: .base64(response.value.audioData),
            warnings: warnings,
            request: .init(body: String(decoding: try encoder.encode(JSONValue.object(requestBodyValues)), as: UTF8.self)),
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue)
        )
    }
}

private struct MistralSpeechResponse: Codable {
    let audioData: String

    enum CodingKeys: String, CodingKey {
        case audioData = "audio_data"
    }
}

private let mistralSpeechResponseSchema = FlexibleSchema(
    Schema<MistralSpeechResponse>.codable(
        MistralSpeechResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
