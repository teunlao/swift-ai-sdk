import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAITranscriptionModel: TranscriptionModelV3 {
    private let modelIdentifier: OpenAITranscriptionModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String

    public init(modelId: OpenAITranscriptionModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        if let prefix = config.provider.split(separator: ".").first {
            self.providerOptionsName = String(prefix)
        } else {
            self.providerOptionsName = "openai"
        }
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        let prepared = try await prepareRequest(options: options)

        var headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }
        headers["Content-Type"] = prepared.contentType

        let response = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/audio/transcriptions")),
            headers: headers,
            body: PostBody(content: .data(prepared.body), values: nil),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAITranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let currentDate = config._internal?.currentDate?() ?? Date()
        let result = mapResponse(response.value)

        return TranscriptionModelV3Result(
            text: result.text,
            segments: result.segments,
            language: result.language,
            durationInSeconds: result.duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            providerMetadata: nil
        )
    }

    // MARK: - Preparation

    private struct PreparedRequest {
        let body: Data
        let contentType: String
        let warnings: [TranscriptionModelV3CallWarning]
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        let warnings: [TranscriptionModelV3CallWarning] = []

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAITranscriptionProviderOptionsSchema
        ) ?? .default

        let providerSpecificOptions: OpenAITranscriptionProviderOptions = try await { () async throws -> OpenAITranscriptionProviderOptions in
            guard providerOptionsName != "openai" else { return .default }
            return try await parseProviderOptions(
                provider: providerOptionsName,
                providerOptions: options.providerOptions,
                schema: openAITranscriptionProviderOptionsSchema
            ) ?? .default
        }()

        var effectiveOptions = OpenAITranscriptionProviderOptions.default

        func apply(_ source: OpenAITranscriptionProviderOptions) {
            if let include = source.include { effectiveOptions.include = include }
            if let language = source.language { effectiveOptions.language = language }
            if let prompt = source.prompt { effectiveOptions.prompt = prompt }
            if let temperature = source.temperature { effectiveOptions.temperature = temperature }
            if let granularities = source.timestampGranularities { effectiveOptions.timestampGranularities = granularities }
        }

        apply(openAIOptions)
        apply(providerSpecificOptions)

        let audioData = try data(from: options.audio)
        let fileExtension = mediaTypeToExtension(options.mediaType)
        let filename = fileExtension.isEmpty ? "audio" : "audio.\(fileExtension)"

        var builder = MultipartFormDataBuilder()
        builder.appendField(name: "model", value: modelIdentifier.rawValue)
        builder.appendFile(name: "file", filename: filename, contentType: options.mediaType, data: audioData)

        if let include = effectiveOptions.include {
            for value in include {
                builder.appendField(name: "include[]", value: value)
            }
        }
        if let language = effectiveOptions.language {
            builder.appendField(name: "language", value: language)
        }
        if let prompt = effectiveOptions.prompt {
            builder.appendField(name: "prompt", value: prompt)
        }

        builder.appendField(name: "response_format", value: responseFormat(for: modelIdentifier))

        if let temperature = effectiveOptions.temperature {
            builder.appendField(name: "temperature", value: String(temperature))
        }
        if let granularities = effectiveOptions.timestampGranularities {
            for granularity in granularities {
                builder.appendField(name: "timestamp_granularities[]", value: granularity)
            }
        }

        let (body, contentType) = builder.build()
        return PreparedRequest(body: body, contentType: contentType, warnings: warnings)
    }

    private func data(from audio: TranscriptionModelV3Audio) throws -> Data {
        switch audio {
        case .binary(let data):
            return data
        case .base64(let base64):
            return try convertBase64ToData(base64)
        }
    }

    private func merge(primary: OpenAITranscriptionProviderOptions?, override: OpenAITranscriptionProviderOptions?) -> OpenAITranscriptionProviderOptions? {
        if primary == nil { return override }
        if override == nil { return primary }
        guard var result = primary, let override else { return nil }

        if let include = override.include { result.include = include }
        if let language = override.language { result.language = language }
        if let prompt = override.prompt { result.prompt = prompt }
        if let temperature = override.temperature { result.temperature = temperature }
        if let granularities = override.timestampGranularities { result.timestampGranularities = granularities }

        return result
    }

    private func responseFormat(for modelId: OpenAITranscriptionModelId) -> String {
        switch modelId.rawValue {
        case "gpt-4o-transcribe", "gpt-4o-mini-transcribe":
            return "json"
        default:
            return "verbose_json"
        }
    }

    // MARK: - Response Mapping

    private struct MappedResponse {
        let text: String
        let segments: [TranscriptionModelV3Result.Segment]
        let language: String?
        let duration: Double?
    }

    private func mapResponse(_ response: OpenAITranscriptionResponse) -> MappedResponse {
        let languageCode = response.language.flatMap { languageLookup[$0] }

        let segments: [TranscriptionModelV3Result.Segment]
        if let responseSegments = response.segments {
            segments = responseSegments.map {
                TranscriptionModelV3Result.Segment(
                    text: $0.text,
                    startSecond: $0.start,
                    endSecond: $0.end
                )
            }
        } else if let words = response.words {
            segments = words.map {
                TranscriptionModelV3Result.Segment(
                    text: $0.word,
                    startSecond: $0.start,
                    endSecond: $0.end
                )
            }
        } else {
            segments = []
        }

        return MappedResponse(
            text: response.text,
            segments: segments,
            language: languageCode,
            duration: response.duration
        )
    }

    private let languageLookup: [String: String] = [
        "afrikaans": "af",
        "arabic": "ar",
        "armenian": "hy",
        "azerbaijani": "az",
        "belarusian": "be",
        "bosnian": "bs",
        "bulgarian": "bg",
        "catalan": "ca",
        "chinese": "zh",
        "croatian": "hr",
        "czech": "cs",
        "danish": "da",
        "dutch": "nl",
        "english": "en",
        "estonian": "et",
        "finnish": "fi",
        "french": "fr",
        "galician": "gl",
        "german": "de",
        "greek": "el",
        "hebrew": "he",
        "hindi": "hi",
        "hungarian": "hu",
        "icelandic": "is",
        "indonesian": "id",
        "italian": "it",
        "japanese": "ja",
        "kannada": "kn",
        "kazakh": "kk",
        "korean": "ko",
        "latvian": "lv",
        "lithuanian": "lt",
        "macedonian": "mk",
        "malay": "ms",
        "marathi": "mr",
        "maori": "mi",
        "nepali": "ne",
        "norwegian": "no",
        "persian": "fa",
        "polish": "pl",
        "portuguese": "pt",
        "romanian": "ro",
        "russian": "ru",
        "serbian": "sr",
        "slovak": "sk",
        "slovenian": "sl",
        "spanish": "es",
        "swahili": "sw",
        "swedish": "sv",
        "tagalog": "tl",
        "tamil": "ta",
        "thai": "th",
        "turkish": "tr",
        "ukrainian": "uk",
        "urdu": "ur",
        "vietnamese": "vi",
        "welsh": "cy"
    ]
}
