import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

public typealias GoogleVertexSpeechModelOptions = GoogleSpeechModelOptions

public final class GoogleVertexCloudTTSSpeechModel: SpeechModelV4 {
    public struct Config: Sendable {
        public let provider: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public init(provider: String, headers: @escaping @Sendable () throws -> [String: String?] = { [:] }, fetch: FetchFunction? = nil) {
            self.provider = provider
            self.headers = headers
            self.fetch = fetch
        }
    }
    private struct Response: Codable, Sendable { let audioContent: String? }
    public let modelId: String
    private let config: Config
    public var provider: String { config.provider }

    public init(modelId: String, config: Config) {
        self.modelId = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let timestamp = Date()
        let voice = options.voice ?? "Kore"
        let language: String
        let name: String
        if let range = voice.range(of: "Chirp3-HD") {
            var prefix = String(voice[..<range.lowerBound])
            if prefix.hasSuffix("-") { prefix.removeLast() }
            language = options.language ?? (prefix.isEmpty ? "en-US" : prefix)
            name = voice
        } else {
            language = options.language ?? "en-US"
            name = "\(language)-Chirp3-HD-\(voice)"
        }
        var warnings: [SharedV4Warning] = []
        if options.instructions != nil {
            warnings.append(.unsupported(feature: "instructions", details: "Google Cloud Text-to-Speech Chirp 3: HD voices do not support the `instructions` option. It was ignored."))
        }
        if let format = options.outputFormat, format != "wav" {
            warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(format). Using wav instead."))
        }
        var audio: JSONObject = ["audioEncoding": .string("LINEAR16")]
        if let speed = options.speed { audio["speakingRate"] = .number(speed) }
        let body: JSONValue = .object([
            "input": .object(["text": .string(options.text)]),
            "voice": .object(["languageCode": .string(language), "name": .string(name)]),
            "audioConfig": .object(audio)
        ])
        let result = try await postJsonToAPI(
            url: "https://texttospeech.googleapis.com/v1/text:synthesize",
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 },
            body: body, failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema.codable(
                Response.self, jsonSchema: .object(["type": .string("object")])
            ))),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let data = try result.value.audioContent.map { try convertBase64ToData($0) } ?? Data()
        let request = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        return .init(
            audio: .binary(data), warnings: warnings, request: .init(body: request),
            response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders, body: result.rawValue),
            providerMetadata: ["google": ["mimeType": .string("audio/wav")]]
        )
    }
}
