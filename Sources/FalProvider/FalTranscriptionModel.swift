import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-transcription-model.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

public final class FalTranscriptionModel: TranscriptionModelV4 {
    public var specificationVersion: String { "v4" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: FalTranscriptionModelId
    private let config: FalConfig

    init(modelId: FalTranscriptionModelId, config: FalConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let currentDate = config.currentDate()
        let prepared = try await prepareRequest(options: options)

        let audioBase64: String
        switch options.audio {
        case .binary(let data):
            audioBase64 = data.base64EncodedString()
        case .base64(let base64):
            audioBase64 = base64
        }

        let audioURL = "data:\(options.mediaType);base64,\(audioBase64)"

        let queueResponse = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "https://queue.fal.run/fal-ai/\(modelIdentifier.rawValue)")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body.merging(["audio_url": .string(audioURL)]) { $1 }),
            failedResponseHandler: falFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falTranscriptionJobSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let requestId = queueResponse.value.requestId

        let (finalResponse, responseHeaders, rawValue) = try await pollForCompletion(
            requestId: requestId,
            headers: options.headers,
            abortSignal: options.abortSignal
        )

        let segments: [TranscriptionModelV4Result.Segment] = finalResponse.chunks?.map { chunk in
            TranscriptionModelV4Result.Segment(
                text: chunk.text,
                startSecond: chunk.timestamp?.first ?? 0,
                endSecond: chunk.timestamp.flatMap { $0.count > 1 ? $0[1] : nil } ?? 0
            )
        } ?? []

        let duration = finalResponse.chunks?.last?.timestamp.flatMap { $0.count > 1 ? $0[1] : nil }
        let language = finalResponse.inferredLanguages?.first

        return TranscriptionModelV4Result(
            text: finalResponse.text,
            segments: segments,
            language: language,
            durationInSeconds: duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV4Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders,
                body: rawValue
            )
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
    }

    private func prepareRequest(options: TranscriptionModelV4CallOptions) async throws -> PreparedRequest {
        var body: [String: JSONValue] = [
            "task": .string("transcribe"),
            "diarize": .bool(true),
            "chunk_level": .string("word")
        ]
        let warnings: [SharedV4Warning] = []

        if let falOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falTranscriptionModelOptionsSchema
        ) {
            body["language"] = falOptions.language.map(JSONValue.string) ?? .null
            if let diarize = falOptions.diarize { body["diarize"] = .bool(diarize) }
            if let chunkLevel = falOptions.chunkLevel { body["chunk_level"] = .string(chunkLevel.rawValue) }
            if let version = falOptions.version { body["version"] = .string(version) }
            if let batchSize = falOptions.batchSize { body["batch_size"] = .number(batchSize) }
            if let numSpeakers = falOptions.numSpeakers { body["num_speakers"] = .number(numSpeakers) }
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func pollForCompletion(
        requestId: String,
        headers: [String: String]?,
        abortSignal: (@Sendable () -> Bool)?
    ) async throws -> (FalTranscriptionResponse, [String: String], Any?) {
        let start = Date().timeIntervalSince1970
        let timeout: TimeInterval = 60

        while true {
            if abortSignal?() == true {
                throw CancellationError()
            }

            do {
                let status = try await getFromAPI(
                    url: config.url(.init(modelId: modelIdentifier.rawValue, path: "https://queue.fal.run/fal-ai/\(modelIdentifier.rawValue)/requests/\(requestId)")),
                    headers: combineHeaders(try config.headers(), headers?.mapValues { Optional($0) }).compactMapValues { $0 },
                    failedResponseHandler: falQueueStatusErrorHandler,
                    successfulResponseHandler: createJsonResponseHandler(responseSchema: falTranscriptionResponseSchema),
                    isAborted: abortSignal,
                    fetch: config.fetch
                )

                return (status.value, status.responseHeaders, status.rawValue)
            } catch {
                if let apiError = error as? APICallError, apiError.message == "Request is still in progress" {
                    if Date().timeIntervalSince1970 - start > timeout {
                        throw FalTranscriptionRequestTimedOutError(
                            message: "Transcription request timed out after 60 seconds"
                        )
                    }
                    try await delay(1000)
                    continue
                }
                throw error
            }
        }
    }
}

private struct FalTranscriptionJobResponse: Decodable, Sendable {
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if !container.contains(.requestId) {
            requestId = "undefined"
        } else {
            requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? "null"
        }
    }
}

private struct FalTranscriptionResponse: Codable, Sendable {
    struct Chunk: Codable, Sendable {
        let text: String
        let timestamp: [Double]?
    }

    let text: String
    let chunks: [Chunk]?
    let inferredLanguages: [String]?

    enum CodingKeys: String, CodingKey {
        case text
        case chunks
        case inferredLanguages = "inferred_languages"
    }
}

private let falTranscriptionJobSchema = FlexibleSchema(
    Schema<FalTranscriptionJobResponse>.codable(
        FalTranscriptionJobResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let falTranscriptionResponseSchema = FlexibleSchema(
    Schema<FalTranscriptionResponse>.codable(
        FalTranscriptionResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let falQueueStatusErrorHandler: ResponseHandler<APICallError> = { input in
    let response = input.response
    let headers = extractResponseHeaders(from: response.httpResponse)
    let data = try await response.body.collectData()
    let bodyText = String(data: data, encoding: .utf8) ?? ""
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let detail = object["detail"] as? String,
       detail == "Request is still in progress" {
        return ResponseHandlerResult(
            value: APICallError(
                message: "Request is still in progress",
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                responseHeaders: headers,
                responseBody: bodyText
            ),
            rawValue: object,
            responseHeaders: headers
        )
    }

    let newResponse = ProviderHTTPResponse(
        url: response.url,
        httpResponse: response.httpResponse,
        body: .data(data)
    )

    let newInput = ResponseHandlerInput(
        url: input.url,
        requestBodyValues: input.requestBodyValues,
        response: newResponse
    )

    return try await falFailedResponseHandler(newInput)
}

private struct FalTranscriptionRequestTimedOutError: AISDKError, Sendable {
    static let errorDomain = "fal.transcription.timeout"

    let name = "TranscriptionRequestTimedOut"
    let message: String
    let cause: (any Error)? = nil
}
