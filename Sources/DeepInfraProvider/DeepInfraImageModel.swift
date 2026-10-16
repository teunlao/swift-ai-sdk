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

public final class DeepInfraImageModel: ImageModelV4 {
    public let specificationVersion: String = "v4"
    public let modelId: String
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var supportsFileInputs: Bool? {
        get async throws {
            ["stabilityai/sd3.5", "black-forest-labs/FLUX-1.1-pro", "black-forest-labs/FLUX-1-schnell",
             "black-forest-labs/FLUX-1-dev", "black-forest-labs/FLUX-pro", "black-forest-labs/FLUX.1-Kontext-dev",
             "black-forest-labs/FLUX.1-Kontext-pro", "Qwen/Qwen-Image-Edit", "stabilityai/sd3.5-medium", "stabilityai/sdxl-turbo"].contains(modelId) ? true : nil
        }
    }
    public var supportsMaskInputs: Bool? { get async throws { try await supportsFileInputs } }

    private let modelIdentifier: DeepInfraImageModelId
    private let config: DeepInfraImageModelConfig

    public init(modelId: DeepInfraImageModelId, config: DeepInfraImageModelConfig) {
        self.modelIdentifier = modelId
        self.modelId = modelId.rawValue
        self.config = config
    }

    public var provider: String { config.provider }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let currentDate = config.currentDate()
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let deepinfraOptions = try await parseProviderOptions(provider: "deepinfra", providerOptions: options.providerOptions, schema: deepInfraImageModelOptionsSchema) ?? [:]

        // Image editing mode - use OpenAI-compatible /images/edits endpoint.
        let files = options.files ?? []
        if !files.isEmpty {
            let prepared = try await prepareEditRequest(
                prompt: options.prompt,
                files: files,
                mask: options.mask,
                n: options.n,
                size: options.size,
                providerOptions: deepinfraOptions
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

            return ImageModelV4GenerateResult(
                images: .base64(response.value.data.map { $0.b64JSON }),
                warnings: [],
                response: ImageModelV4ResponseInfo(
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
            let parts = size.components(separatedBy: "x")
            payload["width"] = .string(parts[0])
            if parts.count > 1 { payload["height"] = .string(parts[1]) }
        }

        if let seed = options.seed {
            payload["seed"] = .number(Double(seed))
        }

        payload.merge(deepinfraOptions) { _, new in new }

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

        return ImageModelV4GenerateResult(
            images: .base64(sanitizedImages),
            warnings: [],
            response: ImageModelV4ResponseInfo(
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
        prompt: String?, files: [ImageModelV4File], mask: ImageModelV4File?, n: Int, size: String?,
        providerOptions: [String: JSONValue]
    ) async throws -> PreparedMultipartRequest {
        var images: [FormDataValue] = []
        for file in files {
            let upload = try await resolveUpload(for: file)
            images.append(.data(upload.data, filename: upload.filename, contentType: upload.contentType))
        }
        var fields: [String: FormDataInputValue?] = [
            "model": .value(.string(modelId)), "prompt": prompt.map { .value(.string($0)) },
            "n": .value(.string(String(n))), "size": size.map { .value(.string($0)) }, "image": .array(images)
        ]
        if let mask {
            let upload = try await resolveUpload(for: mask)
            fields["mask"] = .value(.data(upload.data, filename: upload.filename, contentType: upload.contentType))
        }
        for (key, value) in providerOptions {
            switch value {
            case .null: fields.removeValue(forKey: key)
            case .array(let values): fields[key] = .array(values.map { .string(stringifyMultipartValue($0)) })
            default: fields[key] = .value(.string(stringifyMultipartValue(value)))
            }
        }
        let form = convertToFormData(fields, useArrayBrackets: false).build()
        return .init(body: form.data, contentType: form.contentType)
    }

    private struct UploadPart: Sendable {
        let filename: String
        let contentType: String?
        let data: Data
    }

    private func resolveUpload(for file: ImageModelV4File) async throws -> UploadPart {
        switch file {
        case let .file(mediaType, data, _):
            let resolvedData: Data
            switch data {
            case .base64(let base64):
                resolvedData = try convertBase64ToData(base64)
            case .binary(let data):
                resolvedData = data
            }

            return UploadPart(filename: "blob", contentType: mediaType, data: resolvedData)

        case let .url(urlString, _):
            let blob = try await downloadBlob(url: urlString)
            return UploadPart(filename: "blob", contentType: blob.mediaType, data: blob.data)
        }
    }

    private func stringifyMultipartValue(_ value: JSONValue, insideArray: Bool = false) -> String {
        switch value {
        case .null: return insideArray ? "" : "null"
        case .string(let string): return string
        case .number(let number):
            if number.isNaN { return "NaN" }
            if number == .infinity { return "Infinity" }
            if number == -.infinity { return "-Infinity" }
            return Int(exactly: number).map(String.init) ?? String(number)
        case .bool(let bool): return bool ? "true" : "false"
        case .array(let values): return values.map { stringifyMultipartValue($0, insideArray: true) }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    private func getEditUrl() -> String {
        // baseURL is typically https://api.deepinfra.com/v1/inference
        // We need to use https://api.deepinfra.com/v1/openai/images/edits
        var baseURL = config.baseURL
        if let range = baseURL.range(of: "/inference") { baseURL.replaceSubrange(range, with: "/openai") }
        return "\(baseURL)/images/edits"
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
