import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-transcription-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class FalTranscriptionModel: TranscriptionModelV3 {
    public var specificationVersion: String { "v3" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: FalTranscriptionModelId
    private let config: FalConfig

    init(modelId: FalTranscriptionModelId, config: FalConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
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
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body.merging(["audio_url": .string(audioURL)]) { $1 }),
            failedResponseHandler: falFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falTranscriptionJobSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let requestId = queueResponse.value.requestId, !requestId.isEmpty else {
            throw APICallError(message: "fal transcription response missing request_id", url: "", requestBodyValues: nil)
        }

        let currentDate = config.currentDate()
        let (finalResponse, responseHeaders, rawValue) = try await pollForCompletion(
            requestId: requestId,
            headers: options.headers,
            abortSignal: options.abortSignal
        )

        let segments: [TranscriptionModelV3Result.Segment] = finalResponse.chunks?.map { chunk in
            TranscriptionModelV3Result.Segment(
                text: chunk.text,
                startSecond: chunk.timestamp?.first ?? 0,
                endSecond: chunk.timestamp?.last ?? 0
            )
        } ?? []

        let duration = finalResponse.chunks?.last?.timestamp?.last
        let language = finalResponse.inferredLanguages?.first

        return TranscriptionModelV3Result(
            text: finalResponse.text,
            segments: segments,
            language: language,
            durationInSeconds: duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders,
                body: rawValue
            )
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        var body: [String: JSONValue] = [
            "task": .string("transcribe"),
            "diarize": .bool(true),
            "chunk_level": .string("word")
        ]
        let warnings: [SharedV3Warning] = []

        if let falOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falTranscriptionOptionsSchema
        ) {
            switch falOptions.language {
            case .value(let language):
                body["language"] = .string(language)
            case .null:
                body["language"] = .null
            }

            body["diarize"] = .bool(falOptions.diarize)
            body["chunk_level"] = .string(falOptions.chunkLevel.rawValue)
            body["version"] = .string(falOptions.version)
            body["batch_size"] = .number(Double(falOptions.batchSize))

            switch falOptions.numSpeakers {
            case .value(let value):
                body["num_speakers"] = .number(Double(value))
            case .null:
                body["num_speakers"] = .null
            case .unspecified:
                break
            }
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
                    headers: combineHeaders(config.headers(), headers?.mapValues { Optional($0) }).compactMapValues { $0 },
                    failedResponseHandler: falQueueStatusErrorHandler,
                    successfulResponseHandler: createJsonResponseHandler(responseSchema: falTranscriptionResponseSchema),
                    isAborted: abortSignal,
                    fetch: config.fetch
                )

                return (status.value, status.responseHeaders, status.rawValue)
            } catch {
                if let apiError = error as? APICallError, apiError.message == "Request is still in progress" {
                    if Date().timeIntervalSince1970 - start > timeout {
                        throw APICallError(message: "Transcription request timed out after 60 seconds", url: "", requestBodyValues: nil)
                    }
                    try await delay(1000)
                    continue
                }
                throw error
            }
        }
    }
}

private struct FalTranscriptionJobResponse: Codable, Sendable {
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
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
