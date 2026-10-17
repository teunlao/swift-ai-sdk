import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayVideoModel: VideoModelV4Generator, VideoModelV4Operations, VideoModelV4WebhookHandler {
    private let modelIdentifier: GatewayVideoModelId
    private let config: GatewayVideoModelConfig

    init(modelId: GatewayVideoModelId, config: GatewayVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v4" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    // Set a very large number to prevent client-side splitting of requests
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(Int.max) }

    public func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult {
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

        let body = try buildRequestBody(options)

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

            return VideoModelV4GenerateResult(
                videos: response.value.videos.map { $0.asVideoData() },
                warnings: response.value.warnings ?? [],
                providerMetadata: response.value.providerMetadata,
                response: VideoModelV4ResponseInfo(
                    timestamp: Date(),
                    modelId: modelIdentifier.rawValue,
                    headers: response.responseHeaders
                )
            )
        } catch {
            throw asGatewayError(error, authMethod: authMethod)
        }
    }

    public func handleWebhookOption(
        webhook: @escaping @Sendable () async throws -> VideoModelV4Webhook
    ) async throws -> VideoModelV4WebhookRegistration {
        let value = try await webhook()
        return .init(webhookUrl: value.url, received: value.received)
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        var body = try buildRequestBody(options)
        if let webhookUrl, !webhookUrl.isEmpty { body["callbackUrl"] = .string(webhookUrl) }
        let headers = try await config.headers()
        do {
            let result = try await postJsonToAPI(
                url: "\(getUrl())/start",
                headers: combineHeaders(headers, options.headers?.mapValues { Optional($0) }, getModelConfigHeaders(), try await config.o11yHeaders()).compactMapValues { $0 },
                body: JSONValue.object(body),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySchema(GatewayVideoStartResponse.self)),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            return .init(
                operation: result.value.operation,
                warnings: result.value.warnings ?? [],
                providerMetadata: result.value.providerMetadata,
                response: .init(timestamp: Date(), modelId: modelId, headers: result.responseHeaders)
            )
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: headers.compactMapValues { $0 }))
        }
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let headers = try await config.headers()
        do {
            let result = try await postJsonToAPI(
                url: "\(getUrl())/status",
                headers: combineHeaders(headers, options.headers?.mapValues { Optional($0) }, getModelConfigHeaders(), try await config.o11yHeaders()).compactMapValues { $0 },
                body: JSONValue.object(["operation": options.operation]),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySchema(GatewayVideoStatusResponse.self)),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            let response = VideoModelV4ResponseInfo(timestamp: Date(), modelId: modelId, headers: result.responseHeaders)
            switch result.value {
            case .pending(let warnings, let metadata):
                return .pending(warnings: warnings ?? [], providerMetadata: metadata, response: response)
            case .completed(let videos, let warnings, let metadata):
                return .completed(videos: videos.map { $0.asVideoData() }, warnings: warnings ?? [], providerMetadata: metadata, response: response)
            case .error(let error, let metadata):
                return .error(error: error, providerMetadata: metadata, response: response)
            case .cancelled(let metadata):
                return .error(error: "Video generation was cancelled.", providerMetadata: metadata, response: response)
            }
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: headers.compactMapValues { $0 }))
        }
    }

    private func buildRequestBody(_ options: VideoModelV4CallOptions) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = ["n": .number(Double(options.n))]
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if let value = options.aspectRatio, !value.isEmpty { body["aspectRatio"] = .string(value) }
        if let value = options.resolution, !value.isEmpty { body["resolution"] = .string(value) }
        if let value = options.duration, value != 0 { body["duration"] = .number(Double(value)) }
        if let value = options.fps, value != 0 { body["fps"] = .number(Double(value)) }
        if let value = options.seed, value != 0 { body["seed"] = .number(Double(value)) }
        if let value = options.generateAudio { body["generateAudio"] = .bool(value) }
        if let value = options.providerOptions { body["providerOptions"] = try gatewayJSON(value) }
        if let value = options.image { body["image"] = try gatewayJSON(value) }
        if let value = options.frameImages { body["frameImages"] = try gatewayJSON(value) }
        if let value = options.inputReferences { body["inputReferences"] = try gatewayJSON(value) }
        return body
    }

    private func getUrl() -> String {
        "\(config.baseURL)/video-model"
    }

    private func getModelConfigHeaders() -> [String: String?] {
        [
            "ai-video-model-specification-version": "4",
            "ai-model-id": modelIdentifier.rawValue
        ]
    }
}

private struct GatewayVideoStartResponse: Decodable, Sendable {
    let operation: JSONValue
    let warnings: [SharedV4Warning]?
    let providerMetadata: SharedV4ProviderMetadata?
}

private enum GatewayVideoStatusResponse: Decodable, Sendable {
    case pending([SharedV4Warning]?, SharedV4ProviderMetadata?)
    case completed([GatewayVideoData], [SharedV4Warning]?, SharedV4ProviderMetadata?)
    case error(String, SharedV4ProviderMetadata?)
    case cancelled(SharedV4ProviderMetadata?)

    private enum CodingKeys: String, CodingKey { case status, warnings, providerMetadata, videos, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
        switch try container.decode(String.self, forKey: .status) {
        case "pending":
            self = .pending(try container.decodeIfPresent([SharedV4Warning].self, forKey: .warnings), metadata)
        case "completed":
            self = .completed(try container.decode([GatewayVideoData].self, forKey: .videos), try container.decodeIfPresent([SharedV4Warning].self, forKey: .warnings), metadata)
        case "error":
            self = .error(try container.decode(String.self, forKey: .error), metadata)
        case "cancelled":
            self = .cancelled(metadata)
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown Gateway video status")
        }
    }
}

private struct GatewayVideoSuccessValue: Decodable, Sendable {
    let videos: [GatewayVideoData]
    let warnings: [SharedV4Warning]?
    let providerMetadata: SharedV4ProviderMetadata?
}

private let gatewayVideoSuccessHandler: ResponseHandler<GatewayVideoSuccessValue> = { input in
    let response = input.response
    let headers = extractResponseHeaders(from: response.httpResponse)
    let contentType = response.httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
    if contentType.contains("application/json") {
        return try await createJsonResponseHandler(responseSchema: gatewaySchema(GatewayVideoSuccessValue.self))(input)
    }
    guard contentType.contains("text/event-stream") else {
        throw GatewayVideoResponseFailure(message: "Unsupported content type: \(contentType)")
    }
    let eventStream = parseJsonEventStream(stream: response.body.makeStream(), schema: gatewayVideoEventSchema)
    var iterator = eventStream.makeAsyncIterator()
    guard let parseResult = try await iterator.next() else {
        throw GatewayVideoResponseFailure(message: "Stream ended without receiving a result event")
    }
    switch parseResult {
    case .success(let event, _):
        switch event {
        case .result(let videos, let warnings, let providerMetadata):
            return ResponseHandlerResult(value: .init(videos: videos, warnings: warnings, providerMetadata: providerMetadata), responseHeaders: headers)
        case .error(let message, let errorType, let statusCode, let param):
            let data: JSONValue = .object(["error": .object(["message": .string(message), "type": .string(errorType), "param": param ?? .null])])
            throw APICallError(
                message: message, url: input.url, requestBodyValues: input.requestBodyValues,
                statusCode: statusCode, responseHeaders: headers,
                responseBody: jsonStringForVideoEventError(message: message, errorType: errorType, statusCode: statusCode, param: param), data: data
            )
        }
    case .failure(let error, _): throw error
    }
}

private struct GatewayVideoResponseFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private enum GatewayVideoEvent: Decodable, Sendable {
    case result(videos: [GatewayVideoData], warnings: [SharedV4Warning]?, providerMetadata: SharedV4ProviderMetadata?)
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
            let warnings = try container.decodeIfPresent([SharedV4Warning].self, forKey: .warnings)
            let providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
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

    func asVideoData() -> VideoModelV4VideoData {
        switch self {
        case .url(let url, let mediaType):
            return .url(url: url, mediaType: mediaType)
        case .base64(let data, let mediaType):
            return .base64(data: data, mediaType: mediaType)
        }
    }
}

private let gatewayVideoEventSchema = gatewaySchema(GatewayVideoEvent.self)

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

