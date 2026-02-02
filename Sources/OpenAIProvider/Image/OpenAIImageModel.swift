import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIImageModel: ImageModelV3 {
    private let modelIdentifier: OpenAIImageModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIImageModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall {
        if let limit = openAIImageModelMaxImagesPerCall[modelIdentifier] {
            return .value(limit)
        }
        // Upstream TypeScript: return modelMaxImagesPerCall[this.modelId] ?? 1
        return .value(1)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        if options.aspectRatio != nil {
            warnings.append(.unsupportedSetting(setting: "aspectRatio", details: "This model does not support aspect ratio. Use `size` instead."))
        }

        if options.seed != nil {
            warnings.append(.unsupportedSetting(setting: "seed", details: nil))
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response: ResponseHandlerResult<OpenAIImageResponse>
        if let files = options.files, !files.isEmpty {
            let prepared = try await prepareEditsRequest(prompt: options.prompt, files: files, mask: options.mask, n: options.n, size: options.size, providerOptions: options.providerOptions)

            var multipartHeaders = headers
            multipartHeaders["Content-Type"] = prepared.contentType

            response = try await postToAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/edits")),
                headers: multipartHeaders,
                body: PostBody(content: .data(prepared.body), values: nil),
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
        } else {
            let body = try makeRequestBody(options: options)
            response = try await postJsonToAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/generations")),
                headers: headers,
                body: body,
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
        }

        let value = response.value
        let images = value.data.map { $0.b64JSON }

        let metadataValue: ImageModelV3ProviderMetadataValue? = {
            let revisions = value.data.map { item -> JSONValue in
                if let prompt = item.revisedPrompt {
                    return .object(["revisedPrompt": .string(prompt)])
                }
                return .null
            }
            if revisions.allSatisfy({ $0 == .null }) {
                return nil
            }
            return ImageModelV3ProviderMetadataValue(images: revisions, additionalData: nil)
        }()

        let providerMetadata: ImageModelV3ProviderMetadata? = metadataValue.map { ["openai": $0] }

        let timestamp = config._internal?.currentDate?() ?? Date()
        let responseInfo = ImageModelV3ResponseInfo(
            timestamp: timestamp,
            modelId: modelIdentifier.rawValue,
            headers: response.responseHeaders
        )

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: responseInfo
        )
    }

    private func makeRequestBody(options: ImageModelV3CallOptions) throws -> JSONValue {
        var payload: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue)
        ]

        if let prompt = options.prompt {
            payload["prompt"] = .string(prompt)
        }

        if options.n > 0 {
            payload["n"] = .number(Double(options.n))
        }
        if let size = options.size {
            payload["size"] = .string(size)
        }

        if !openAIImageHasDefaultResponseFormat(modelId: modelIdentifier) {
            payload["response_format"] = .string("b64_json")
        }

        if let openaiOptions = options.providerOptions?["openai"], !openaiOptions.isEmpty {
            for (key, value) in openaiOptions {
                payload[key] = value
            }
        }

        return .object(payload)
    }

    private struct PreparedMultipartRequest {
        let body: Data
        let contentType: String
    }

    private func prepareEditsRequest(
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

        if n > 0 {
            builder.appendField(name: "n", value: String(n))
        }
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

        if let openaiOptions = providerOptions?["openai"], !openaiOptions.isEmpty {
            for (key, value) in openaiOptions {
                guard let string = stringifyMultipartValue(value) else { continue }
                builder.appendField(name: key, value: string)
            }
        }

        let (body, contentType) = builder.build()
        return PreparedMultipartRequest(body: body, contentType: contentType)
    }

    private struct UploadPart {
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
}
