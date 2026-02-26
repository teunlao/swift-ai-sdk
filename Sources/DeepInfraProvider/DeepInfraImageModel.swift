import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepinfra/src/deepinfra-image-model.ts
// Upstream commit: 73d5c5920e
//===----------------------------------------------------------------------===//

public struct DeepInfraImageModelConfig: Sendable {
    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () -> [String: String?]
    public let fetch: FetchFunction?
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

public final class DeepInfraImageModel: ImageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelId: String
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: DeepInfraImageModelId
    private let config: DeepInfraImageModelConfig

    public init(modelId: DeepInfraImageModelId, config: DeepInfraImageModelConfig) {
        self.modelIdentifier = modelId
        self.modelId = modelId.rawValue
        self.config = config
    }

    public var provider: String { config.provider }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        let currentDate = config.currentDate()
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })

        // Image editing mode - use OpenAI-compatible /images/edits endpoint.
        let files = options.files ?? []
        if !files.isEmpty {
            let prepared = try await prepareEditRequest(
                prompt: options.prompt,
                files: files,
                mask: options.mask,
                n: options.n,
                size: options.size,
                providerOptions: options.providerOptions
            )

            var multipartHeaders = headers
            multipartHeaders["Content-Type"] = prepared.contentType

            let response = try await postToAPI(
                url: getEditUrl(),
                headers: multipartHeaders.compactMapValues { $0 },
                body: PostBody(content: .data(prepared.body), values: nil),
                failedResponseHandler: deepInfraEditFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: deepInfraEditResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            return ImageModelV3GenerateResult(
                images: .base64(response.value.data.map { $0.b64JSON }),
                warnings: [],
                response: ImageModelV3ResponseInfo(
                    timestamp: currentDate,
                    modelId: modelIdentifier.rawValue,
                    headers: response.responseHeaders
                )
            )
        }

        // Standard image generation mode.
        var payload: [String: JSONValue] = [:]

        if let prompt = options.prompt {
            payload["prompt"] = .string(prompt)
        }

        payload["num_images"] = .number(Double(options.n))

        if let aspectRatio = options.aspectRatio {
            payload["aspect_ratio"] = .string(aspectRatio)
        }

        if let size = options.size {
            let parts = size.split(separator: "x", omittingEmptySubsequences: true)
            if parts.count == 2 {
                payload["width"] = .string(String(parts[0]))
                payload["height"] = .string(String(parts[1]))
            }
        }

        if let seed = options.seed {
            payload["seed"] = .number(Double(seed))
        }

        if let providerOptions = options.providerOptions?["deepinfra"] {
            for (key, value) in providerOptions {
                payload[key] = value
            }
        }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/\(modelIdentifier.rawValue)",
            headers: headers.compactMapValues { $0 },
            body: JSONValue.object(payload),
            failedResponseHandler: deepInfraFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: deepInfraImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let sanitizedImages = response.value.images.map { image -> String in
            image.replacingOccurrences(of: "^data:image/\\w+;base64,", with: "", options: [.regularExpression])
        }

        return ImageModelV3GenerateResult(
            images: .base64(sanitizedImages),
            warnings: [],
            response: ImageModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }

    private struct PreparedMultipartRequest: Sendable {
        let body: Data
        let contentType: String
    }

    private func prepareEditRequest(
        prompt: String?,
        files: [ImageModelV3File],
        mask: ImageModelV3File?,
        n: Int,
        size: String?,
        providerOptions: SharedV3ProviderOptions?
    ) async throws -> PreparedMultipartRequest {
        var builder = MultipartFormDataBuilder()
        builder.appendField(name: "model", value: modelIdentifier.rawValue)

        if let prompt {
            builder.appendField(name: "prompt", value: prompt)
        }

        builder.appendField(name: "n", value: String(n))
        if let size {
            builder.appendField(name: "size", value: size)
        }

        for file in files {
            let upload = try await resolveUpload(for: file, defaultFilename: "image")
            builder.appendFile(name: "image", filename: upload.filename, contentType: upload.contentType, data: upload.data)
        }

        if let mask {
            let upload = try await resolveUpload(for: mask, defaultFilename: "mask")
            builder.appendFile(name: "mask", filename: upload.filename, contentType: upload.contentType, data: upload.data)
        }

        if let deepinfraOptions = providerOptions?["deepinfra"], !deepinfraOptions.isEmpty {
            for (key, value) in deepinfraOptions {
                guard let string = stringifyMultipartValue(value) else { continue }
                builder.appendField(name: key, value: string)
            }
        }

        let (data, contentType) = builder.build()
        return PreparedMultipartRequest(body: data, contentType: contentType)
    }

    private struct UploadPart: Sendable {
        let filename: String
        let contentType: String
        let data: Data
    }

    private func resolveUpload(for file: ImageModelV3File, defaultFilename: String) async throws -> UploadPart {
        switch file {
        case let .file(mediaType, data, _):
            let resolvedData: Data
            switch data {
            case .base64(let base64):
                resolvedData = try convertBase64ToData(base64)
            case .binary(let data):
                resolvedData = data
            }

            let ext = mediaTypeToExtension(mediaType)
            let filename = ext.isEmpty ? defaultFilename : "\(defaultFilename).\(ext)"
            return UploadPart(filename: filename, contentType: mediaType, data: resolvedData)

        case let .url(urlString, _):
            guard let url = URL(string: urlString) else {
                throw URLError(.badURL)
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            return UploadPart(filename: defaultFilename, contentType: "application/octet-stream", data: data)
        }
    }

    private func stringifyMultipartValue(_ value: JSONValue) -> String? {
        switch value {
        case .null:
            return nil
        case .string(let string):
            return string
        case .number(let number):
            if number.rounded(.towardZero) == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            guard let data = try? encoder.encode(value) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private func getEditUrl() -> String {
        // baseURL is typically https://api.deepinfra.com/v1/inference
        // We need to use https://api.deepinfra.com/v1/openai/images/edits
        let baseUrl = config.baseURL.replacingOccurrences(of: "/inference", with: "/openai")
        return "\(baseUrl)/images/edits"
    }
}

// MARK: - Response Handling

private struct DeepInfraImageError: Codable, Sendable {
    struct Detail: Codable, Sendable {
        let error: String
    }

    let detail: Detail
}

private let deepInfraFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<DeepInfraImageError>.codable(
            DeepInfraImageError.self,
            jsonSchema: .object(["type": .string("object")])
        )
    ),
    errorToMessage: { $0.detail.error }
)

private struct DeepInfraImageResponse: Codable, Sendable {
    let images: [String]
}

private let deepInfraImageResponseSchema = FlexibleSchema(
    Schema<DeepInfraImageResponse>.codable(
        DeepInfraImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct DeepInfraEditError: Codable, Sendable {
    struct Detail: Codable, Sendable {
        let message: String
    }

    let error: Detail?
}

private let deepInfraEditFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<DeepInfraEditError>.codable(
            DeepInfraEditError.self,
            jsonSchema: .object(["type": .string("object")])
        )
    ),
    errorToMessage: { $0.error?.message ?? "Unknown error" }
)

private struct DeepInfraEditResponse: Codable, Sendable {
    struct Item: Codable, Sendable {
        let b64JSON: String

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [Item]
}

private let deepInfraEditResponseSchema = FlexibleSchema(
    Schema<DeepInfraEditResponse>.codable(
        DeepInfraEditResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
