import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-transcription-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class DeepgramTranscriptionModel: TranscriptionModelV3 {
    struct Config: Sendable {
        struct RequestOptions: Sendable {
            let modelId: DeepgramTranscriptionModelId
            let path: String
        }

        let provider: String
        let url: @Sendable (RequestOptions) -> String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let currentDate: @Sendable () -> Date
    }

    private struct PreparedRequest {
        let url: String
        let headers: [String: String]
        let body: Data
        let warnings: [TranscriptionModelV3CallWarning]
    }

    private let modelIdentifier: DeepgramTranscriptionModelId
    private let config: Config

    init(modelId: DeepgramTranscriptionModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        let prepared = try await prepareRequest(options: options)

        let response = try await postToAPI(
            url: prepared.url,
            headers: prepared.headers,
            body: PostBody(content: .data(prepared.body), values: nil),
            failedResponseHandler: deepgramFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: deepgramTranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let transcriptText = response.value.results?.channels.first?.alternatives.first?.transcript ?? ""
        let words = response.value.results?.channels.first?.alternatives.first?.words ?? []
        let segments = words.map {
            TranscriptionModelV3Result.Segment(text: $0.word, startSecond: $0.start, endSecond: $0.end)
        }

        let timestamp = config.currentDate()
        let duration = response.value.metadata?.duration

        return TranscriptionModelV3Result(
            text: transcriptText,
            segments: segments,
            language: nil,
            durationInSeconds: duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            providerMetadata: nil
        )
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        let deepgramOptions = try await parseProviderOptions(
            provider: "deepgram",
            providerOptions: options.providerOptions,
            schema: deepgramTranscriptionOptionsSchema
        )

        let audioData: Data
        switch options.audio {
        case .binary(let data):
            audioData = data
        case .base64(let base64):
            audioData = try convertBase64ToData(base64)
        }

        let baseURL = config.url(.init(modelId: modelIdentifier, path: "/v1/listen"))
        var queryItems: [URLQueryItem] = []

        func append(_ name: String, value: String) {
            queryItems.append(URLQueryItem(name: name, value: value))
        }

        func append(_ name: String, bool value: Bool) {
            append(name, value: value ? "true" : "false")
        }

        func append(_ name: String, double value: Double) {
            var formatted = String(value)
            if formatted.contains("e") || formatted.contains("E") {
                formatted = String(format: "%g", value)
            }
            append(name, value: formatted)
        }

        append("model", value: modelIdentifier.rawValue)

        let diarizeDefault = deepgramOptions?.diarize ?? true
        append("diarize", bool: diarizeDefault)

        if let language = deepgramOptions?.language {
            append("language", value: language)
        }

        if let smartFormat = deepgramOptions?.smartFormat {
            append("smart_format", bool: smartFormat)
        }

        if let punctuate = deepgramOptions?.punctuate {
            append("punctuate", bool: punctuate)
        }

        if let paragraphs = deepgramOptions?.paragraphs {
            append("paragraphs", bool: paragraphs)
        }

        if let summarize = deepgramOptions?.summarize {
            switch summarize {
            case .v2:
                append("summarize", value: "v2")
            case .disabled:
                append("summarize", value: "false")
            }
        }

        if let topics = deepgramOptions?.topics {
            append("topics", bool: topics)
        }

        if let intents = deepgramOptions?.intents {
            append("intents", bool: intents)
        }

        if let sentiment = deepgramOptions?.sentiment {
            append("sentiment", bool: sentiment)
        }

        if let detectEntities = deepgramOptions?.detectEntities {
            append("detect_entities", bool: detectEntities)
        }

        if let redact = deepgramOptions?.redact {
            switch redact {
            case .single(let value):
                append("redact", value: value)
            case .multiple(let values):
                append("redact", value: values.joined(separator: ","))
            }
        }

        if let replace = deepgramOptions?.replace {
            append("replace", value: replace)
        }

        if let search = deepgramOptions?.search {
            append("search", value: search)
        }

        if let keyterm = deepgramOptions?.keyterm {
            append("keyterm", value: keyterm)
        }

        if let utterances = deepgramOptions?.utterances {
            append("utterances", bool: utterances)
        }

        if let uttSplit = deepgramOptions?.uttSplit {
            append("utt_split", double: uttSplit)
        }

        if let fillerWords = deepgramOptions?.fillerWords {
            append("filler_words", bool: fillerWords)
        }

        let queryString: String
        if queryItems.isEmpty {
            queryString = ""
        } else {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=?")
            let encoded = queryItems.compactMap { item -> String? in
                guard let value = item.value else { return nil }
                guard let keyEncoded = item.name.addingPercentEncoding(withAllowedCharacters: allowed),
                      let valueEncoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                    return nil
                }
                return "\(keyEncoded)=\(valueEncoded)"
            }
            queryString = encoded.joined(separator: "&")
        }

        let finalURL = queryString.isEmpty ? baseURL : "\(baseURL)?\(queryString)"

        var headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        headers["Content-Type"] = options.mediaType

        return PreparedRequest(
            url: finalURL,
            headers: headers,
            body: audioData,
            warnings: []
        )
    }
}

private struct DeepgramTranscriptionResponse: Codable {
    struct Metadata: Codable {
        let duration: Double?
    }

    struct Results: Codable {
        struct Channel: Codable {
            struct Alternative: Codable {
                struct Word: Codable {
                    let word: String
                    let start: Double
                    let end: Double
                }

                let transcript: String
                let words: [Word]?
            }

            let alternatives: [Alternative]
        }

        let channels: [Channel]
    }

    let metadata: Metadata?
    let results: Results?
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let deepgramTranscriptionResponseSchema = FlexibleSchema(
    Schema<DeepgramTranscriptionResponse>.codable(
        DeepgramTranscriptionResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
