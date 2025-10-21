import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GroqTranscriptionProviderOptions: Sendable, Equatable {
    var language: String?
    var prompt: String?
    var responseFormat: String?
    var temperature: Double?
    var timestampGranularities: [String]?
}

private let groqTranscriptionOptionsSchema = FlexibleSchema(
    Schema<GroqTranscriptionProviderOptions>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true)
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "groq", issues: "transcription options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = GroqTranscriptionProviderOptions()

                if let languageValue = dict["language"], languageValue != .null {
                    guard case .string(let language) = languageValue else {
                        let error = SchemaValidationIssuesError(vendor: "groq", issues: "language must be a string")
                        return .failure(error: TypeValidationError.wrap(value: languageValue, cause: error))
                    }
                    options.language = language
                }

                if let promptValue = dict["prompt"], promptValue != .null {
                    guard case .string(let prompt) = promptValue else {
                        let error = SchemaValidationIssuesError(vendor: "groq", issues: "prompt must be a string")
                        return .failure(error: TypeValidationError.wrap(value: promptValue, cause: error))
                    }
                    options.prompt = prompt
                }

                if let responseFormatValue = dict["responseFormat"], responseFormatValue != .null {
                    guard case .string(let format) = responseFormatValue else {
                        let error = SchemaValidationIssuesError(vendor: "groq", issues: "responseFormat must be a string")
                        return .failure(error: TypeValidationError.wrap(value: responseFormatValue, cause: error))
                    }
                    options.responseFormat = format
                }

                if let temperatureValue = dict["temperature"], temperatureValue != .null {
                    guard case .number(let number) = temperatureValue else {
                        let error = SchemaValidationIssuesError(vendor: "groq", issues: "temperature must be a number")
                        return .failure(error: TypeValidationError.wrap(value: temperatureValue, cause: error))
                    }
                    options.temperature = number
                }

                if let granularitiesValue = dict["timestampGranularities"], granularitiesValue != .null {
                    guard case .array(let array) = granularitiesValue else {
                        let error = SchemaValidationIssuesError(vendor: "groq", issues: "timestampGranularities must be an array")
                        return .failure(error: TypeValidationError.wrap(value: granularitiesValue, cause: error))
                    }
                    var result: [String] = []
                    for element in array {
                        guard case .string(let granularity) = element else {
                            let error = SchemaValidationIssuesError(vendor: "groq", issues: "timestampGranularities must be an array of strings")
                            return .failure(error: TypeValidationError.wrap(value: element, cause: error))
                        }
                        result.append(granularity)
                    }
                    options.timestampGranularities = result
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

public final class GroqTranscriptionModel: TranscriptionModelV3 {
    struct Config: Sendable {
        struct RequestOptions {
            let modelId: GroqTranscriptionModelId
            let path: String
        }

        let provider: String
        let url: @Sendable (RequestOptions) -> String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let currentDate: @Sendable () -> Date
    }

    private let modelIdentifier: GroqTranscriptionModelId
    private let config: Config

    init(modelId: GroqTranscriptionModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public let specificationVersion: String = "v3"
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        let prepared = try await prepareRequest(options: options)
        let url = config.url(.init(modelId: modelIdentifier, path: "/audio/transcriptions"))

        let response = try await postToAPI(
            url: url,
            headers: prepared.headers,
            body: PostBody(content: .data(prepared.body), values: nil),
            failedResponseHandler: groqFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: groqTranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let mapped = mapResponse(response.value)
        let timestamp = config.currentDate()

        return TranscriptionModelV3Result(
            text: mapped.text,
            segments: mapped.segments,
            language: mapped.language,
            durationInSeconds: mapped.duration,
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

    private struct PreparedRequest {
        let body: Data
        let headers: [String: String]
        let warnings: [TranscriptionModelV3CallWarning]
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        let groqOptions = try await parseProviderOptions(
            provider: "groq",
            providerOptions: options.providerOptions,
            schema: groqTranscriptionOptionsSchema
        )

        let audioData: Data
        switch options.audio {
        case .binary(let data):
            audioData = data
        case .base64(let base64):
            audioData = try convertBase64ToData(base64)
        }

        var builder = MultipartFormDataBuilder()
        builder.appendField(name: "model", value: modelIdentifier.rawValue)

        let fileExtension = mediaTypeToExtension(options.mediaType)
        let filename = fileExtension.isEmpty ? "audio" : "audio.\(fileExtension)"
        builder.appendFile(name: "file", filename: filename, contentType: options.mediaType, data: audioData)

        if let groqOptions {
            if let language = groqOptions.language {
                builder.appendField(name: "language", value: language)
            }
            if let prompt = groqOptions.prompt {
                builder.appendField(name: "prompt", value: prompt)
            }
            if let responseFormat = groqOptions.responseFormat {
                builder.appendField(name: "response_format", value: responseFormat)
            }
            if let temperature = groqOptions.temperature {
                builder.appendField(name: "temperature", value: String(temperature))
            }
            if let granularities = groqOptions.timestampGranularities, !granularities.isEmpty {
                let joined = granularities.joined(separator: ",")
                builder.appendField(name: "timestamp_granularities", value: joined)
            }
        }

        let (body, contentType) = builder.build()

        var headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        headers["Content-Type"] = contentType

        return PreparedRequest(body: body, headers: headers, warnings: [])
    }

    private struct GroqTranscriptionResponse: Codable {
        struct Segment: Codable {
            let text: String
            let start: Double
            let end: Double
        }

        let text: String
        let language: String?
        let duration: Double?
        let segments: [Segment]?
    }

    private func mapResponse(_ response: GroqTranscriptionResponse) -> (text: String, segments: [TranscriptionModelV3Result.Segment], language: String?, duration: Double?) {
        let segments = response.segments?.map { segment in
            TranscriptionModelV3Result.Segment(
                text: segment.text,
                startSecond: segment.start,
                endSecond: segment.end
            )
        } ?? []

        return (
            text: response.text,
            segments: segments,
            language: response.language,
            duration: response.duration
        )
    }

    private let groqTranscriptionResponseSchema = FlexibleSchema(
        Schema<GroqTranscriptionResponse>.codable(
            GroqTranscriptionResponse.self,
            jsonSchema: genericJSONObjectSchema
        )
    )
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])
