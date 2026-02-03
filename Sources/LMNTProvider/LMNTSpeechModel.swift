import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Config

struct LMNTConfig: Sendable {
    let provider: String
    let url: @Sendable (_ options: (modelId: String, path: String)) -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        url: @escaping @Sendable (_ options: (modelId: String, path: String)) -> String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

// MARK: - Provider Options schema

private struct LMNTSpeechCallOptions: Codable, Sendable {
    var model: String? // 'aurora' | 'blizzard' | string
    var format: String? // 'aac' | 'mp3' | 'mulaw' | 'raw' | 'wav'
    var sampleRate: Int? // 8000 | 16000 | 24000
    var speed: Double? // 0.25..2
    var seed: Int?
    var conversational: Bool?
    var length: Double? // up to 300
    var topP: Double? // 0..1
    var temperature: Double? // >=0
}

private let lmntSpeechCallOptionsSchema = FlexibleSchema(
    Schema<LMNTSpeechCallOptions>.codable(
        LMNTSpeechCallOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

// MARK: - Speech Model

public final class LMNTSpeechModel: SpeechModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: LMNTSpeechModelId
    private let config: LMNTConfig

    init(_ modelId: LMNTSpeechModelId, config: LMNTConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let now = config.currentDate()

        // Parse provider options for 'lmnt'
        let parsedOptions = try await parseProviderOptions(
            provider: "lmnt",
            providerOptions: options.providerOptions,
            schema: lmntSpeechCallOptionsSchema
        )

        var warnings: [SharedV3Warning] = []

        // Build request body
        var body: [String: Any] = [
            "model": modelIdentifier.rawValue,
            "text": options.text,
            "voice": options.voice ?? "ava",
            "response_format": "mp3"
        ]

        if let speed = options.speed { body["speed"] = speed }
        if let language = options.language { body["language"] = language }

        if let output = options.outputFormat {
            let allowed = ["aac", "mp3", "mulaw", "raw", "wav"]
            if allowed.contains(output) {
                body["response_format"] = output
            } else {
                warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(output). Using mp3 instead."))
            }
        }

        if let parsedOptions {
            // Map to API fields (snake_case)
            if let conversational = parsedOptions.conversational { body["conversational"] = conversational }
            if let length = parsedOptions.length { body["length"] = length }
            if let seed = parsedOptions.seed { body["seed"] = seed }
            if let speed = parsedOptions.speed { body["speed"] = speed }
            if let temperature = parsedOptions.temperature { body["temperature"] = temperature }
            if let topP = parsedOptions.topP { body["top_p"] = topP }
            if let sampleRate = parsedOptions.sampleRate { body["sample_rate"] = sampleRate }
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url((modelId: modelIdentifier.rawValue, path: "/v1/ai/speech/bytes")),
            headers: normalizedHeaders,
            body: JSONValue.object(Dictionary(uniqueKeysWithValues: body.map { ($0.key, JSONValue.from(any: $0.value)) })),
            failedResponseHandler: lmntFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let reqBodyString: String? = {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return SpeechModelV3Result(
            audio: .binary(response.value),
            warnings: warnings,
            request: .init(body: reqBodyString),
            response: .init(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}

private extension JSONValue {
    static func from(any: Any) -> JSONValue {
        switch any {
        case let v as String: return .string(v)
        case let v as Int: return .number(Double(v))
        case let v as Double: return .number(v)
        case let v as Bool: return .bool(v)
        default:
            return .null
        }
    }
}
