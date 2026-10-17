import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class DeepgramTranscriptionModel: TranscriptionModelV4 {
    private let identifier: DeepgramTranscriptionModelId
    private let config: DeepgramConfig
    init(modelId: DeepgramTranscriptionModelId, config: DeepgramConfig) { identifier = modelId; self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let now = config.currentDate()
        let settings = try await parseProviderOptions(provider: "deepgram", providerOptions: options.providerOptions, schema: deepgramTranscriptionModelOptionsSchema)
        var query = QueryParameters()
        query["model"] = modelId
        if let settings {
            query["detect_entities"] = settings.detectEntities.map(String.init)
            query["detect_language"] = settings.detectLanguage.map(String.init)
            query["diarize"] = settings.diarize.map(String.init)
            query["filler_words"] = settings.fillerWords.map(String.init)
            query["intents"] = settings.intents.map(String.init)
            query["keyterm"] = settings.keyterm
            query["language"] = settings.language
            query["paragraphs"] = settings.paragraphs.map(String.init)
            query["punctuate"] = settings.punctuate.map(String.init)
            if let redact = settings.redact {
                switch redact { case .single(let string): query["redact"] = string; case .multiple(let strings): query["redact"] = strings.joined(separator: ",") }
            }
            query["replace"] = settings.replace
            query["search"] = settings.search
            query["sentiment"] = settings.sentiment.map(String.init)
            query["smart_format"] = settings.smartFormat.map(String.init)
            if let summarize = settings.summarize { query["summarize"] = summarize == .v2 ? "v2" : "false" }
            query["topics"] = settings.topics.map(String.init)
            query["utterances"] = settings.utterances.map(String.init)
            query["utt_split"] = settings.uttSplit.map(numberString)
        }
        let audio: Data
        switch options.audio {
        case .binary(let value): audio = value
        case .base64(let value): audio = try convertBase64ToData(value)
        }
        let response = try await postToAPI(
            url: query.url("https://api.deepgram.com/v1/listen"),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some), ["Content-Type": options.mediaType]).compactMapValues { $0 },
            body: .init(content: .data(audio), values: audio),
            failedResponseHandler: deepgramFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: deepgramTranscriptionResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let channel = response.value.results?.channels.first
        let alternative = channel?.alternatives.first
        let duration = response.value.metadata?.duration
        return .init(text: alternative?.transcript ?? "",
                     segments: alternative?.words.map { .init(text: $0.word, startSecond: $0.start, endSecond: $0.end) } ?? [],
                     language: channel?.detectedLanguage, durationInSeconds: duration,
                     usage: duration.map { ["seconds": .number($0)] },
                     response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders, body: response.rawValue))
    }
}

private struct DeepgramTranscriptionResponse: Decodable {
    struct Metadata: Decodable { let duration: Double }
    struct Results: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable {
                struct Word: Decodable { let word: String; let start: Double; let end: Double }
                let transcript: String
                let words: [Word]
            }
            let detectedLanguage: String?
            let alternatives: [Alternative]
            enum CodingKeys: String, CodingKey { case alternatives; case detectedLanguage = "detected_language" }
        }
        let channels: [Channel]
    }
    let metadata: Metadata?
    let results: Results?
}
private let deepgramTranscriptionResponseSchema = FlexibleSchema(
    Schema<DeepgramTranscriptionResponse>.codable(DeepgramTranscriptionResponse.self, jsonSchema: ["type": "object"])
)
