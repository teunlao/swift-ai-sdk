import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-video-model.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

public final class GatewayVideoModel: VideoModelV3 {
    private let modelIdentifier: GatewayVideoModelId
    private let config: GatewayVideoModelConfig

    init(modelId: GatewayVideoModelId, config: GatewayVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    // Set a very large number to prevent client-side splitting of requests
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(Int.max) }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let resolvedHeaders = try await resolve(config.headers)
        let authMethod = parseAuthMethod(from: resolvedHeaders.compactMapValues { $0 })

        let o11yHeaders = try await resolve(config.o11yHeaders)
        let requestHeaders = combineHeaders(
            resolvedHeaders,
            options.headers?.mapValues { Optional($0) },
            getModelConfigHeaders(),
            o11yHeaders,
            ["accept": "text/event-stream"]
        ).compactMapValues { $0 }

        var body: [String: JSONValue] = [
            "n": .number(Double(options.n))
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let aspectRatio = options.aspectRatio {
            body["aspectRatio"] = .string(aspectRatio)
        }

        if let resolution = options.resolution {
            body["resolution"] = .string(resolution)
        }

        if let duration = options.duration {
            body["duration"] = .number(Double(duration))
        }

        if let fps = options.fps {
            body["fps"] = .number(Double(fps))
        }

        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        if let providerOptions = options.providerOptions {
            body["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        if let image = options.image {
            body["image"] = encodeVideoFile(image)
        }

        do {
            let response = try await postJsonToAPI(
                url: getUrl(),
                headers: requestHeaders,
                body: JSONValue.object(body),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: gatewayVideoSuccessHandler,
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            return VideoModelV3GenerateResult(
                videos: response.value.videos.map { $0.asVideoData() },
                warnings: response.value.warnings ?? [],
                providerMetadata: response.value.providerMetadata,
                response: VideoModelV3ResponseInfo(
                    timestamp: Date(),
                    modelId: modelIdentifier.rawValue,
                    headers: response.responseHeaders
                )
            )
        } catch {
            throw asGatewayError(error, authMethod: authMethod)
        }
    }

    private func getUrl() -> String {
        "\(config.baseURL)/video-model"
    }

    private func getModelConfigHeaders() -> [String: String?] {
        [
            "ai-video-model-specification-version": "3",
            "ai-model-id": modelIdentifier.rawValue
        ]
    }
}

private struct GatewayVideoSuccessValue: Sendable {
    let videos: [GatewayVideoData]
    let warnings: [SharedV3Warning]?
    let providerMetadata: SharedV3ProviderMetadata?
}

private let gatewayVideoSuccessHandler: ResponseHandler<GatewayVideoSuccessValue> = { input in
    let response = input.response

    guard case .none = response.body else {
        let headers = extractResponseHeaders(from: response.httpResponse)
        let eventStream = parseJsonEventStream(
            stream: response.body.makeStream(),
            schema: gatewayVideoEventSchema
        )

        var iterator = eventStream.makeAsyncIterator()
        guard let parseResult = try await iterator.next() else {
            throw APICallError(
                message: "SSE stream ended without a data event",
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode
            )
        }

        switch parseResult {
        case .success(let event, _):
            switch event {
            case .result(let videos, let warnings, let providerMetadata):
                return ResponseHandlerResult(
                    value: GatewayVideoSuccessValue(
                        videos: videos,
                        warnings: warnings,
                        providerMetadata: providerMetadata
                    ),
                    responseHeaders: headers
                )

            case .error(let message, let errorType, let statusCode, let param):
                let data: JSONValue = .object([
                    "error": .object([
                        "message": .string(message),
                        "type": .string(errorType),
                        "param": param ?? .null
                    ])
                ])

                throw APICallError(
                    message: message,
                    url: input.url,
                    requestBodyValues: input.requestBodyValues,
                    statusCode: statusCode,
                    responseHeaders: headers,
                    responseBody: jsonStringForVideoEventError(message: message, errorType: errorType, statusCode: statusCode, param: param),
                    data: data
                )
            }

        case .failure(let error, _):
            throw APICallError(
                message: "Failed to parse video SSE event",
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                cause: error
            )
        }
    }

    throw APICallError(
        message: "SSE response body is empty",
        url: input.url,
        requestBodyValues: input.requestBodyValues,
        statusCode: response.statusCode
    )
}

private enum GatewayVideoEvent: Decodable, Sendable {
    case result(videos: [GatewayVideoData], warnings: [SharedV3Warning]?, providerMetadata: SharedV3ProviderMetadata?)
    case error(message: String, errorType: String, statusCode: Int, param: JSONValue?)

    private enum CodingKeys: String, CodingKey {
        case type
        case videos
        case warnings
        case providerMetadata
        case message
        case errorType
        case statusCode
        case param
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "result":
            let videos = try container.decode([GatewayVideoData].self, forKey: .videos)
            let warnings = try container.decodeIfPresent([SharedV3Warning].self, forKey: .warnings)
            let providerMetadata = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerMetadata)
            self = .result(videos: videos, warnings: warnings, providerMetadata: providerMetadata)

        case "error":
            let message = try container.decode(String.self, forKey: .message)
            let errorType = try container.decode(String.self, forKey: .errorType)
            let statusCode = try container.decode(Int.self, forKey: .statusCode)
            let param = try container.decodeIfPresent(JSONValue.self, forKey: .param)
            self = .error(message: message, errorType: errorType, statusCode: statusCode, param: param)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unexpected GatewayVideoEvent type: \(type)"
            )
        }
    }
}

private enum GatewayVideoData: Decodable, Sendable, Equatable {
    case url(url: String, mediaType: String)
    case base64(data: String, mediaType: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case data
        case mediaType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let mediaType = try container.decode(String.self, forKey: .mediaType)

        switch type {
        case "url":
            let url = try container.decode(String.self, forKey: .url)
            self = .url(url: url, mediaType: mediaType)
        case "base64":
            let data = try container.decode(String.self, forKey: .data)
            self = .base64(data: data, mediaType: mediaType)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unexpected GatewayVideoData type: \(type)"
            )
        }
    }

    func asVideoData() -> VideoModelV3VideoData {
        switch self {
        case .url(let url, let mediaType):
            return .url(url: url, mediaType: mediaType)
        case .base64(let data, let mediaType):
            return .base64(data: data, mediaType: mediaType)
        }
    }
}

private let gatewayVideoEventSchema = FlexibleSchema(
    Schema<GatewayVideoEvent>.codable(
        GatewayVideoEvent.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)

private func encodeVideoFile(_ file: VideoModelV3File) -> JSONValue {
    switch file {
    case let .file(mediaType, data, providerOptions):
        var payload: [String: JSONValue] = [
            "type": .string("file"),
            "mediaType": .string(mediaType),
            "data": .string(encodedVideoFileData(data))
        ]

        if let providerOptions {
            payload["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        return .object(payload)

    case let .url(url, providerOptions):
        var payload: [String: JSONValue] = [
            "type": .string("url"),
            "url": .string(url)
        ]

        if let providerOptions {
            payload["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        return .object(payload)
    }
}

private func encodedVideoFileData(_ data: VideoModelV3FileData) -> String {
    switch data {
    case .base64(let string):
        return string
    case .binary(let binary):
        return binary.base64EncodedString()
    }
}

private func jsonStringForVideoEventError(
    message: String,
    errorType: String,
    statusCode: Int,
    param: JSONValue?
) -> String? {
    let foundationParam = param.map { jsonValueToFoundation($0) } ?? NSNull()
    let payload: [String: Any] = [
        "type": "error",
        "message": message,
        "errorType": errorType,
        "statusCode": statusCode,
        "param": foundationParam
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        return nil
    }

    return text
}

