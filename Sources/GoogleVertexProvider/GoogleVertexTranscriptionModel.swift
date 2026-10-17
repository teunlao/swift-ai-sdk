import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

public struct GoogleVertexTranscriptionModelOptions: Sendable, Equatable, Codable {
    public var languageCodes: [String]?
    public var enableAutomaticPunctuation: Bool?
    public var enableWordTimeOffsets: Bool?
    public var region: String?
    public init(languageCodes: [String]? = nil, enableAutomaticPunctuation: Bool? = nil, enableWordTimeOffsets: Bool? = nil, region: String? = nil) {
        self.languageCodes = languageCodes
        self.enableAutomaticPunctuation = enableAutomaticPunctuation
        self.enableWordTimeOffsets = enableWordTimeOffsets
        self.region = region
    }
}

public struct GoogleVertexTranscriptionModelGeminiOptions: Sendable, Equatable, Codable {
    public enum Mode: String, Sendable, Codable { case smart = "SMART", verbatim = "VERBATIM" }
    public var languageCodes: [String]?
    public var customVocabulary: [String]?
    public var wordTimestamp: Bool?
    public var diarization: Bool?
    public var mode: Mode?
    public init(languageCodes: [String]? = nil, customVocabulary: [String]? = nil, wordTimestamp: Bool? = nil, diarization: Bool? = nil, mode: Mode? = nil) {
        self.languageCodes = languageCodes
        self.customVocabulary = customVocabulary
        self.wordTimestamp = wordTimestamp
        self.diarization = diarization
        self.mode = mode
    }
}

private let cloudOptionsSchema = vertexOptionsSchema(GoogleVertexTranscriptionModelOptions.self, keys: ["languageCodes", "enableAutomaticPunctuation", "enableWordTimeOffsets", "region"])
private let geminiOptionsSchema = vertexOptionsSchema(GoogleVertexTranscriptionModelGeminiOptions.self, keys: ["languageCodes", "customVocabulary", "wordTimestamp", "diarization", "mode"])

private func vertexOptionsSchema<Value: Codable & Sendable>(_ type: Value.Type, keys: [String]) -> FlexibleSchema<Value> {
    FlexibleSchema(Schema<Value>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
        do {
            let json = try jsonValue(from: value)
            guard case .object(let object) = json else {
                throw InvalidArgumentError(argument: "providerOptions", message: "Provider options must be an object")
            }
            for key in keys where object[key] == .null {
                throw InvalidArgumentError(argument: key, message: "\(key) must not be null")
            }
            let parsed = try JSONDecoder().decode(type, from: JSONEncoder().encode(json))
            return .success(value: parsed)
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }))
}

private struct TranscriptionWord: Codable, Sendable {
    let word: String?
    let startOffset: String?
    let endOffset: String?
    var segment: TranscriptionModelV4Result.Segment? {
        guard let word, let start = vertexDuration(startOffset), let end = vertexDuration(endOffset) else { return nil }
        return .init(text: word, startSecond: start, endSecond: end)
    }
}

private func vertexDuration(_ value: String?) -> Double? {
    guard let value else { return nil }
    guard let range = value.range(of: "^\\s*[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?", options: .regularExpression),
          let number = Double(value[range].trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { return nil }
    return number
}

public final class GoogleVertexTranscriptionModel: TranscriptionModelV4 {
    struct Config: Sendable {
        let provider: String
        let project: @Sendable () throws -> String
        let location: @Sendable () throws -> String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
    }
    private struct Response: Codable, Sendable {
        struct Recognition: Codable, Sendable {
            struct Alternative: Codable, Sendable {
                let transcript: String?
                let words: [TranscriptionWord]?
            }
            let alternatives: [Alternative]?
            let languageCode: String?
        }
        struct Metadata: Codable, Sendable { let totalBilledDuration: String? }
        let results: [Recognition]?
        let metadata: Metadata?
    }
    public let modelId: String
    private let config: Config
    public var provider: String { config.provider }
    init(modelId: String, config: Config) { self.modelId = modelId; self.config = config }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let headers = combineHeaders(try config.headers(), options.headers).compactMapValues { $0 }
        let timestamp = Date()
        let parsed = try await parseVertexOptions(options.providerOptions, schema: cloudOptionsSchema, namespaces: ["googleVertex", "vertex", "google"])
        let region = try parsed?.region ?? config.location()
        guard isVertexHostnamePart(region) else {
            throw InvalidArgumentError(argument: parsed?.region == nil ? "location" : "region", message: "Invalid Google Cloud Speech-to-Text region. Expected a single DNS label (letters, digits, and hyphens).")
        }
        let content: String
        switch options.audio {
        case .binary(let data): content = data.base64EncodedString()
        case .base64(let data): content = data
        }
        let body: JSONValue = .object([
            "config": .object([
                "model": .string(modelId), "languageCodes": .array((parsed?.languageCodes ?? ["auto"]).map(JSONValue.string)),
                "autoDecodingConfig": .object([:]),
                "features": .object([
                    "enableWordTimeOffsets": .bool(parsed?.enableWordTimeOffsets ?? true),
                    "enableAutomaticPunctuation": .bool(parsed?.enableAutomaticPunctuation ?? true)
                ])
            ]), "content": .string(content)
        ])
        let host = region == "global" ? "speech.googleapis.com" : "\(region)-speech.googleapis.com"
        let result = try await postJsonToAPI(
            url: "https://\(host)/v2/projects/\(try config.project())/locations/\(region)/recognizers/_:recognize",
            headers: headers, body: body,
            failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema.codable(
                Response.self, jsonSchema: .object(["type": .string("object")])
            ))), isAborted: options.abortSignal, fetch: config.fetch
        )
        let results = result.value.results ?? []
        let text = results.map { $0.alternatives?.first?.transcript ?? "" }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap { $0.alternatives?.first?.words?.compactMap(\.segment) ?? [] }
        let code = results.first?.languageCode.map { Locale(identifier: $0).language.languageCode?.identifier }
        let language = code.flatMap { $0 }.flatMap { $0.count == 2 ? $0 : nil }
        return .init(text: text, segments: segments, language: language,
                     durationInSeconds: vertexDuration(result.value.metadata?.totalBilledDuration),
                     response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders, body: result.rawValue))
    }
}

public final class GoogleVertexGeminiTranscriptionModel: TranscriptionModelV4 {
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public let resolveBaseURL: (@Sendable () throws -> String)?
        public let webSocket: GoogleWebSocketFactory?
        public let project: String?
        public let location: String?
        public let liveRequest: (@Sendable (String, [String: String]) async throws -> GoogleTranscriptionModel.LiveRequest)?
        public init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?] = { [:] }, fetch: FetchFunction? = nil, resolveBaseURL: (@Sendable () throws -> String)? = nil, webSocket: GoogleWebSocketFactory? = nil, project: String? = nil, location: String? = nil, liveRequest: (@Sendable (String, [String: String]) async throws -> GoogleTranscriptionModel.LiveRequest)? = nil) {
            self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch
            self.resolveBaseURL = resolveBaseURL
            self.webSocket = webSocket; self.project = project; self.location = location; self.liveRequest = liveRequest
        }
    }
    private struct Response: Codable, Sendable {
        struct Candidate: Codable, Sendable {
            struct Content: Codable, Sendable {
                struct Part: Codable, Sendable {
                    struct Transcription: Codable, Sendable {
                        let text: String?
                        let languageCode: String?
                        let words: [TranscriptionWord]?
                    }
                    let text: String?
                    let audioTranscription: Transcription?
                }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
        let usageMetadata: JSONObject?
    }
    public let modelId: String
    private let config: Config
    public var provider: String { config.provider }
    public init(modelId: String, config: Config) { self.modelId = modelId; self.config = config }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        let config = self.config
        let liveRequest: @Sendable (String, [String: String]) async throws -> GoogleTranscriptionModel.LiveRequest = config.liveRequest ?? { modelId, headers in
            guard let project = config.project, let location = config.location else {
                throw LoadSettingError(message: "Google Vertex project and location are required for live transcription")
            }
            guard isVertexHostnamePart(location) else {
                throw InvalidArgumentError(argument: "location", message: "Invalid Google Vertex location")
            }
            let host = vertexHost(location)
            let url = URL(string: "wss://\(host)/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent")!
            return .init(url: url, model: "projects/\(project)/locations/\(location)/publishers/google/models/\(modelId)", headers: headers)
        }
        let model = GoogleTranscriptionModel(modelId: modelId, config: .init(
            provider: provider, baseURL: config.baseURL, headers: config.headers, fetch: config.fetch,
            webSocket: config.webSocket, resolveBaseURL: config.resolveBaseURL, liveRequest: liveRequest
        ))
        return try await model.doStream(options: options)
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        if modelId.contains("-live") {
            throw InvalidArgumentError(argument: "modelId", message: "Model '\(modelId)' only supports streaming transcription. Use a unary model such as 'gemini-3.5-transcribe'.")
        }
        let timestamp = Date()
        let parsed = try await parseVertexOptions(options.providerOptions, schema: geminiOptionsSchema, namespaces: ["googleVertex", "vertex", "google"])
        let content: String
        switch options.audio {
        case .binary(let data): content = data.base64EncodedString()
        case .base64(let data): content = data
        }
        var body: JSONObject = ["contents": .array([.object([
            "role": .string("user"), "parts": .array([.object(["inlineData": .object([
                "mimeType": .string(options.mediaType), "data": .string(content)
            ])])])
        ])])]
        if let parsed {
            let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(parsed))
            if case .object(let config) = encoded, !config.isEmpty {
                body["generationConfig"] = .object(["audioTranscriptionConfig": .object(config)])
            }
        }
        let result = try await postJsonToAPI(
            url: "\(try config.resolveBaseURL?() ?? config.baseURL)/models/\(modelId):generateContent",
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema.codable(
                Response.self, jsonSchema: .object(["type": .string("object")])
            ))), isAborted: options.abortSignal, fetch: config.fetch
        )
        let parts = result.value.candidates?.first?.content?.parts ?? []
        let plain = parts.map { $0.text ?? "" }.joined()
        let transcription = parts.map { $0.audioTranscription?.text ?? "" }.joined()
        let language = parts.compactMap { $0.audioTranscription?.languageCode }.first
        let segments = parts.flatMap { $0.audioTranscription?.words?.compactMap(\.segment) ?? [] }
        return .init(
            text: plain.isEmpty ? transcription : plain, segments: segments, language: language,
            usage: result.value.usageMetadata,
            response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders, body: result.rawValue),
            providerMetadata: result.value.usageMetadata.map { ["google": ["usageMetadata": .object($0)]] }
        )
    }
}
