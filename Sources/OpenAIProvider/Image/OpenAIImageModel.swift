import Foundation
import AISDKProvider
import AISDKProviderUtils

private struct OpenAIImageModelCore: Sendable {
    private let modelIdentifier: OpenAIImageModelId
    private let config: OpenAIConfig

    init(modelId: OpenAIImageModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    var maxImagesPerCall: Int {
        openAIImageModelMaxImagesPerCall[modelIdentifier] ?? 1
    }

    func doGenerate(
        prompt: String?,
        n: Int,
        size: String?,
        aspectRatio: String?,
        seed: Int?,
        files: [OpenAIImageInputFile]?,
        mask: OpenAIImageInputFile?,
        providerOptions: SharedV4ProviderOptions?,
        abortSignal: (@Sendable () -> Bool)?,
        headers: SharedV4Headers?
    ) async throws -> OpenAIImageCoreResult {
        var warnings: [SharedV4Warning] = []

        if aspectRatio != nil {
            warnings.append(.unsupported(
                feature: "aspectRatio",
                details: "This model does not support aspect ratio. Use `size` instead."
            ))
        }

        if seed != nil {
            warnings.append(.unsupported(feature: "seed", details: nil))
        }

        let timestamp = config._internal?.currentDate?() ?? Date()
        let combinedHeaders = combineHeaders(try config.headers(), headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }

        let response: ResponseHandlerResult<OpenAIImageResponse>
        if let files {
            let prepared = try await prepareEditsRequest(
                prompt: prompt,
                files: files,
                mask: mask,
                n: n,
                size: size,
                providerOptions: providerOptions
            )

            var multipartHeaders = combinedHeaders
            multipartHeaders["Content-Type"] = prepared.contentType

            response = try await postToAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/edits")),
                headers: multipartHeaders,
                body: PostBody(content: .data(prepared.body), values: nil),
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
                isAborted: abortSignal,
                fetch: config.fetch
            )
        } else {
            let body = try await makeGenerationRequestBody(
                prompt: prompt,
                n: n,
                size: size,
                providerOptions: providerOptions
            )

            response = try await postJsonToAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/generations")),
                headers: combinedHeaders,
                body: body,
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
                isAborted: abortSignal,
                fetch: config.fetch
            )
        }

        let value = response.value
        let images = value.data.map { $0.b64JSON }
        let metadata: ImageModelV4ProviderMetadata = [
            "openai": ImageModelV4ProviderMetadataValue(
                images: makeOpenAIImageMetadataEntries(value),
                additionalData: nil
            )
        ]

        return OpenAIImageCoreResult(
            images: images,
            warnings: warnings,
            providerMetadata: metadata,
            response: ImageModelV4ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            ),
            usage: value.usage.map {
                ImageModelV4Usage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            }
        )
    }

    private func makeOpenAIImageMetadataEntries(_ response: OpenAIImageResponse) -> [JSONValue] {
        let total = max(response.data.count, 1)

        return response.data.enumerated().map { index, item in
            var metadata: [String: JSONValue] = [:]

            if let revisedPrompt = item.revisedPrompt {
                metadata["revisedPrompt"] = .string(revisedPrompt)
            }
            if let created = response.created {
                metadata["created"] = .number(created)
            }
            if let size = response.size {
                metadata["size"] = .string(size)
            }
            if let quality = response.quality {
                metadata["quality"] = .string(quality)
            }
            if let background = response.background {
                metadata["background"] = .string(background)
            }
            if let outputFormat = response.outputFormat {
                metadata["outputFormat"] = .string(outputFormat)
            }

            let tokenDetails = distributeInputTokenDetails(
                details: response.usage?.inputTokensDetails,
                index: index,
                total: total
            )
            for (key, value) in tokenDetails {
                metadata[key] = value
            }

            return .object(metadata)
        }
    }

    private func distributeInputTokenDetails(
        details: OpenAIImageResponse.Usage.InputTokensDetails?,
        index: Int,
        total: Int
    ) -> [String: JSONValue] {
        guard let details, total > 0 else {
            return [:]
        }

        var result: [String: JSONValue] = [:]

        if let imageTokens = details.imageTokens {
            let base = imageTokens / total
            let remainder = imageTokens - base * (total - 1)
            let distributed = (index == total - 1) ? remainder : base
            result["imageTokens"] = .number(Double(distributed))
        }

        if let textTokens = details.textTokens {
            let base = textTokens / total
            let remainder = textTokens - base * (total - 1)
            let distributed = (index == total - 1) ? remainder : base
            result["textTokens"] = .number(Double(distributed))
        }

        return result
    }

    private func makeGenerationRequestBody(
        prompt: String?,
        n: Int,
        size: String?,
        providerOptions: SharedV4ProviderOptions?
    ) async throws -> JSONValue {
        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openAIImageModelGenerationOptionsSchema
        )

        var payload: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "n": .number(Double(n))
        ]

        if let prompt {
            payload["prompt"] = .string(prompt)
        }
        if let size {
            payload["size"] = .string(size)
        }
        if let quality = openAIOptions?.quality {
            payload["quality"] = .string(quality)
        }
        if let style = openAIOptions?.style {
            payload["style"] = .string(style)
        }
        if let background = openAIOptions?.background {
            payload["background"] = .string(background)
        }
        if let moderation = openAIOptions?.moderation {
            payload["moderation"] = .string(moderation)
        }
        if let outputFormat = openAIOptions?.outputFormat {
            payload["output_format"] = .string(outputFormat)
        }
        if let outputCompression = openAIOptions?.outputCompression {
            payload["output_compression"] = .number(outputCompression)
        }
        if let user = openAIOptions?.user {
            payload["user"] = .string(user)
        }

        if !openAIImageHasDefaultResponseFormat(modelId: modelIdentifier) {
            payload["response_format"] = .string("b64_json")
        }

        return .object(payload)
    }

    private struct PreparedMultipartRequest {
        let body: Data
        let contentType: String
    }

    private func prepareEditsRequest(
        prompt: String?,
        files: [OpenAIImageInputFile],
        mask: OpenAIImageInputFile?,
        n: Int,
        size: String?,
        providerOptions: SharedV4ProviderOptions?
    ) async throws -> PreparedMultipartRequest {
        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openAIImageModelEditOptionsSchema
        )

        var builder = MultipartFormDataBuilder()
        builder.appendField(name: "model", value: modelIdentifier.rawValue)
        if let prompt {
            builder.appendField(name: "prompt", value: prompt)
        }

        builder.appendField(name: "n", value: String(n))
        if let size {
            builder.appendField(name: "size", value: size)
        }

        let imageFieldName = files.count > 1 ? "image[]" : "image"
        for file in files {
            let upload = try await resolveUpload(for: file, defaultFilename: "image")
            builder.appendFile(name: imageFieldName, filename: upload.filename, contentType: upload.contentType, data: upload.data)
        }

        if let mask {
            let upload = try await resolveUpload(for: mask, defaultFilename: "mask")
            builder.appendFile(name: "mask", filename: upload.filename, contentType: upload.contentType, data: upload.data)
        }

        appendMultipartField(builder: &builder, name: "quality", value: openAIOptions?.quality.map(JSONValue.string))
        appendMultipartField(builder: &builder, name: "background", value: openAIOptions?.background.map(JSONValue.string))
        appendMultipartField(builder: &builder, name: "output_format", value: openAIOptions?.outputFormat.map(JSONValue.string))
        appendMultipartField(builder: &builder, name: "output_compression", value: openAIOptions?.outputCompression.map(JSONValue.number))
        appendMultipartField(builder: &builder, name: "input_fidelity", value: openAIOptions?.inputFidelity.map(JSONValue.string))
        appendMultipartField(builder: &builder, name: "user", value: openAIOptions?.user.map(JSONValue.string))

        let (body, contentType) = builder.build()
        return PreparedMultipartRequest(body: body, contentType: contentType)
    }

    private func appendMultipartField(builder: inout MultipartFormDataBuilder, name: String, value: JSONValue?) {
        guard let value, let string = stringifyMultipartValue(value) else { return }
        builder.appendField(name: name, value: string)
    }

    private struct UploadPart {
        let filename: String
        let contentType: String
        let data: Data
    }

    private func resolveUpload(for file: OpenAIImageInputFile, defaultFilename: String) async throws -> UploadPart {
        switch file {
        case let .file(mediaType, data):
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

        case let .url(urlString):
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

private struct OpenAIImageCoreResult: Sendable {
    let images: [String]
    let warnings: [SharedV4Warning]
    let providerMetadata: ImageModelV4ProviderMetadata
    let response: ImageModelV4ResponseInfo
    let usage: ImageModelV4Usage?
}

private enum OpenAIImageInputFile: Sendable {
    case file(mediaType: String, data: OpenAIImageInputFileData)
    case url(String)
}

private enum OpenAIImageInputFileData: Sendable {
    case base64(String)
    case binary(Data)
}

public final class OpenAIImageModel: ImageModelV3 {
    private let core: OpenAIImageModelCore

    public init(modelId: OpenAIImageModelId, config: OpenAIConfig) {
        self.core = OpenAIImageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall {
        .value(core.maxImagesPerCall)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        let result = try await core.doGenerate(
            prompt: options.prompt,
            n: options.n,
            size: options.size,
            aspectRatio: options.aspectRatio,
            seed: options.seed,
            files: convertImageModelV3FilesToOpenAIInput(options.files),
            mask: options.mask.map(convertImageModelV3FileToOpenAIInput),
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            headers: options.headers
        )

        return ImageModelV3GenerateResult(
            images: .base64(result.images),
            warnings: result.warnings.map(convertSharedV4WarningToV3),
            providerMetadata: convertOpenAIImageProviderMetadataToV3(result.providerMetadata),
            response: ImageModelV3ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers
            ),
            usage: result.usage.map {
                ImageModelV3Usage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            }
        )
    }

    func asV4() -> OpenAIImageModelV4 {
        OpenAIImageModelV4(core: core)
    }
}

public final class OpenAIImageModelV4: ImageModelV4 {
    private let core: OpenAIImageModelCore

    public init(modelId: OpenAIImageModelId, config: OpenAIConfig) {
        self.core = OpenAIImageModelCore(modelId: modelId, config: config)
    }

    fileprivate init(core: OpenAIImageModelCore) {
        self.core = core
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall {
        .value(core.maxImagesPerCall)
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let result = try await core.doGenerate(
            prompt: options.prompt,
            n: options.n,
            size: options.size,
            aspectRatio: options.aspectRatio,
            seed: options.seed,
            files: options.files?.map(convertImageModelV4FileToOpenAIInput),
            mask: options.mask.map(convertImageModelV4FileToOpenAIInput),
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            headers: options.headers
        )

        return ImageModelV4GenerateResult(
            images: .base64(result.images),
            warnings: result.warnings,
            providerMetadata: result.providerMetadata,
            response: result.response,
            usage: result.usage
        )
    }
}

private func convertImageModelV3FilesToOpenAIInput(_ files: [ImageModelV3File]?) -> [OpenAIImageInputFile]? {
    guard let files, !files.isEmpty else { return nil }
    return files.map(convertImageModelV3FileToOpenAIInput)
}

private func convertImageModelV3FileToOpenAIInput(_ value: ImageModelV3File) -> OpenAIImageInputFile {
    switch value {
    case let .file(mediaType, data, _):
        return .file(mediaType: mediaType, data: convertImageModelV3FileDataToOpenAIInput(data))
    case let .url(url, _):
        return .url(url)
    }
}

private func convertImageModelV3FileDataToOpenAIInput(_ value: ImageModelV3FileData) -> OpenAIImageInputFileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func convertImageModelV4FileToOpenAIInput(_ value: ImageModelV4File) -> OpenAIImageInputFile {
    switch value {
    case let .file(mediaType, data, _):
        return .file(mediaType: mediaType, data: convertImageModelV4FileDataToOpenAIInput(data))
    case let .url(url, _):
        return .url(url)
    }
}

private func convertImageModelV4FileDataToOpenAIInput(_ value: ImageModelV4FileData) -> OpenAIImageInputFileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func convertOpenAIImageProviderMetadataToV3(
    _ value: ImageModelV4ProviderMetadata?
) -> ImageModelV3ProviderMetadata? {
    value?.mapValues { ImageModelV3ProviderMetadataValue(images: $0.images, additionalData: $0.additionalData) }
}

private func convertSharedV4WarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        return .other(message: "\(setting): \(message)")
    case let .other(message):
        return .other(message: message)
    }
}
