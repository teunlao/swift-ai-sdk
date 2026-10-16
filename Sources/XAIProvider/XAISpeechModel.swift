import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAISpeechModelOptions: Codable, Sendable, Equatable {
    public var sampleRate: Int?
    public var bitRate: Int?
    public var optimizeStreamingLatency: Int?
    public var textNormalization: Bool?
    public var withTimestamps: Bool?
    public var replace: [String: String]?
    public init(sampleRate: Int? = nil, bitRate: Int? = nil, optimizeStreamingLatency: Int? = nil, textNormalization: Bool? = nil, withTimestamps: Bool? = nil, replace: [String: String]? = nil) {
        self.sampleRate = sampleRate; self.bitRate = bitRate; self.optimizeStreamingLatency = optimizeStreamingLatency; self.textNormalization = textNormalization; self.withTimestamps = withTimestamps; self.replace = replace
    }
}

private let speechOptionsSchema = FlexibleSchema(Schema<XAISpeechModelOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        let options = try JSONDecoder().decode(XAISpeechModelOptions.self, from: JSONEncoder().encode(json))
        if let value = options.sampleRate, ![8000, 16000, 22050, 24000, 44100, 48000].contains(value) { throw InvalidArgumentError(argument: "sampleRate", message: "Invalid sample rate") }
        if let value = options.bitRate, ![32000, 64000, 96000, 128000, 192000].contains(value) { throw InvalidArgumentError(argument: "bitRate", message: "Invalid MP3 bit rate") }
        if let value = options.optimizeStreamingLatency, !(0...2).contains(value) { throw InvalidArgumentError(argument: "optimizeStreamingLatency", message: "Expected 0, 1, or 2") }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

struct XAISpeechModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

private struct SpeechEnvelope: Codable, Sendable {
    struct Timestamps: Codable, Sendable {
        let graphChars: [String]
        let graphTimes: [[Double]]
        enum CodingKeys: String, CodingKey { case graphChars = "graph_chars", graphTimes = "graph_times" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            graphChars = try c.decode([String].self, forKey: .graphChars)
            graphTimes = try c.decode([[Double]].self, forKey: .graphTimes)
            guard graphTimes.allSatisfy({ $0.count == 2 }) else { throw DecodingError.dataCorruptedError(forKey: .graphTimes, in: c, debugDescription: "Expected start/end time pairs") }
        }
    }
    let audio: String?
    let contentType: String?
    let duration: Double?
    let timestamps: Timestamps?
    enum CodingKeys: String, CodingKey { case audio, contentType = "content_type", duration, timestamps = "audio_timestamps" }
}

public final class XAISpeechModel: SpeechModelV4 {
    public var provider: String { config.provider }
    public let modelId = ""
    private let config: XAISpeechModelConfig
    init(config: XAISpeechModelConfig) { self.config = config }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let timestamp = Date()
        let xai = try await parseProviderOptions(provider: "xai", providerOptions: options.providerOptions, schema: speechOptionsSchema) ?? .init()
        var warnings: [SharedV4Warning] = []
        var codec = options.outputFormat ?? "mp3"
        if !["mp3", "wav", "pcm", "mulaw", "alaw"].contains(codec) {
            warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(codec). Using mp3 instead."))
            codec = "mp3"
        }
        if options.instructions != nil { warnings.append(.unsupported(feature: "instructions", details: "xAI speech models do not support the `instructions` option. Use xAI speech tags in `text` to control delivery.")) }
        var format: [String: JSONValue] = ["codec": .string(codec)]
        if let value = xai.sampleRate { format["sample_rate"] = .number(Double(value)) }
        if let value = xai.bitRate {
            if codec == "mp3" { format["bit_rate"] = .number(Double(value)) }
            else { warnings.append(.unsupported(feature: "providerOptions", details: "xAI `bitRate` is supported only for mp3 output. It was ignored.")) }
        }
        var body: [String: JSONValue] = ["text": .string(options.text), "voice_id": .string(options.voice ?? "eve"), "language": .string(options.language ?? "auto"), "output_format": .object(format)]
        if let value = options.speed { body["speed"] = .number(value) }
        if let value = xai.optimizeStreamingLatency { body["optimize_streaming_latency"] = .number(Double(value)) }
        if let value = xai.textNormalization { body["text_normalization"] = .bool(value) }
        if let value = xai.withTimestamps { body["with_timestamps"] = .bool(value) }
        if let value = xai.replace { body["replace"] = .object(value.mapValues(JSONValue.string)) }
        let handler: ResponseHandler<(Data, SpeechEnvelope?)>
        if xai.withTimestamps == true {
            handler = { input in
                let schema = FlexibleSchema(Schema<SpeechEnvelope>.codable(SpeechEnvelope.self, jsonSchema: .object(["type": .string("object")])))
                let response = try await createJsonResponseHandler(responseSchema: schema)(input)
                let audio = try response.value.audio.map(convertBase64ToData) ?? Data()
                return .init(value: (audio, response.value), rawValue: response.rawValue, responseHeaders: response.responseHeaders)
            }
        } else {
            handler = { input in
                let response = try await createBinaryResponseHandler()(input)
                return .init(value: (response.value, nil), rawValue: response.rawValue, responseHeaders: response.responseHeaders)
            }
        }
        let response = try await postJsonToAPI(url: "\(config.baseURL)/tts", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, body: JSONValue.object(body), failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: handler, isAborted: options.abortSignal, fetch: config.fetch)
        var metadata: [String: JSONValue] = [:]
        if let value = response.responseHeaders["x-trace-id"] { metadata["traceId"] = .string(value) }
        if let value = response.value.1?.duration { metadata["duration"] = .number(value) }
        if let value = response.value.1?.contentType { metadata["contentType"] = .string(value) }
        if let value = response.value.1?.timestamps {
            metadata["audioTimestamps"] = .object(["graphChars": .array(value.graphChars.map(JSONValue.string)), "graphTimes": .array(value.graphTimes.map { .array($0.map(JSONValue.number)) })])
        }
        return .init(audio: .binary(response.value.0), warnings: warnings, request: .init(body: String(decoding: try JSONEncoder().encode(JSONValue.object(body)), as: UTF8.self)), response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue), providerMetadata: ["xai": metadata])
    }
}
