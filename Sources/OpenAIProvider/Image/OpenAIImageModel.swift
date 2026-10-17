import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIImageModel: ImageModelV4 {
    private let modelIdentifier: OpenAIImageModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIImageModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall {
        .value(getMaxImagesPerCall(modelId: modelIdentifier))
    }
    public var supportsFileInputs: Bool? {
        if let capabilities = config.imageInputCapabilities { return capabilities.supportsFileInputs }
        if modelId == "dall-e-3" { return false }
        return modelMaxImagesPerCall[modelIdentifier] != nil ? true : nil
    }
    public var supportsMaskInputs: Bool? {
        if let capabilities = config.imageInputCapabilities { return capabilities.supportsMaskInputs }
        return supportsFileInputs
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []
        if options.aspectRatio != nil {
            warnings.append(.unsupported(feature: "aspectRatio", details: "This model does not support aspect ratio. Use `size` instead."))
        }
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
        let timestamp = config._internal?.currentDate?() ?? Date()
        let response: ResponseHandlerResult<OpenAIImageResponse>

        if let files = options.files {
            let settings = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions,
                schema: openAIImageModelEditOptionsSchema)
            let url = try config.url(.init(modelId: modelId, path: "/images/edits"))
            let headers = try requestHeaders(options.headers)
            let images = try await imageParts(files, abortSignal: options.abortSignal)
            let mask: FormDataValue?
            if let file = options.mask { mask = try await blob(file, abortSignal: options.abortSignal) }
            else { mask = nil }
            let fields: [(String, FormDataInputValue?)] = [
                ("model", .value(.string(modelId))),
                ("prompt", options.prompt.map { .value(.string($0)) }),
                ("image", .array(images)),
                ("mask", mask.map(FormDataInputValue.value)),
                ("n", .value(.string(String(options.n)))),
                ("size", options.size.map { .value(.string($0)) }),
                ("quality", settings?.quality.map { .value(.string($0)) }),
                ("background", settings?.background.map { .value(.string($0)) }),
                ("output_format", settings?.outputFormat.map { .value(.string($0)) }),
                ("output_compression", settings?.outputCompression.map { .value(.string(String($0))) }),
                ("input_fidelity", settings?.inputFidelity.map { .value(.string($0)) }),
                ("user", settings?.user.map { .value(.string($0)) })
            ]
            let form = convertToFormData(fields)
            response = try await postToAPI(url: url, headers: headers,
                body: PostBody(content: .multipartFormData(form), values: form.values),
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
                isAborted: options.abortSignal, fetch: config.fetch)
        } else {
            let settings = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions,
                schema: openAIImageModelGenerationOptionsSchema)
            let url = try config.url(.init(modelId: modelId, path: "/images/generations"))
            let headers = try requestHeaders(options.headers)
            var body: JSONObject = ["model": .string(modelId), "n": .number(Double(options.n))]
            if let prompt = options.prompt { body["prompt"] = .string(prompt) }
            if let size = options.size { body["size"] = .string(size) }
            if let quality = settings?.quality { body["quality"] = .string(quality) }
            if let style = settings?.style { body["style"] = .string(style) }
            if let background = settings?.background { body["background"] = .string(background) }
            if let moderation = settings?.moderation { body["moderation"] = .string(moderation) }
            if let format = settings?.outputFormat { body["output_format"] = .string(format) }
            if let compression = settings?.outputCompression { body["output_compression"] = .number(Double(compression)) }
            if let user = settings?.user { body["user"] = .string(user) }
            if !hasDefaultResponseFormat(modelId: modelId) { body["response_format"] = .string("b64_json") }
            response = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body),
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
                isAborted: options.abortSignal, fetch: config.fetch)
        }

        let value = response.value
        return ImageModelV4GenerateResult(
            images: .base64(value.data.map(\.b64JSON)), warnings: warnings,
            providerMetadata: ["openai": .init(images: metadata(value))],
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders),
            usage: value.usage.map { .init(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, totalTokens: $0.totalTokens) }
        )
    }

    private func requestHeaders(_ headers: SharedV4Headers?) throws -> [String: String] {
        combineHeaders(try config.headers(), headers?.mapValues(Optional.some)).compactMapValues { $0 }
    }

    private struct ImagePart: Sendable {
        let index: Int
        let value: FormDataValue
    }

    private func imageParts(_ files: [ImageModelV4File], abortSignal: (@Sendable () -> Bool)?) async throws -> [FormDataValue] {
        try await withThrowingTaskGroup(of: ImagePart.self) { group in
            for (index, file) in files.enumerated() {
                group.addTask { ImagePart(index: index, value: try await self.blob(file, abortSignal: abortSignal)) }
            }
            var parts: [ImagePart] = []
            for try await part in group { parts.append(part) }
            return parts.sorted { $0.index < $1.index }.map(\.value)
        }
    }

    private func blob(_ file: ImageModelV4File, abortSignal: (@Sendable () -> Bool)?) async throws -> FormDataValue {
        switch file {
        case .file(let mediaType, let data, _):
            let bytes: Data
            switch data {
            case .binary(let value): bytes = value
            case .base64(let value): bytes = try convertBase64ToData(value)
            }
            return .data(bytes, contentType: mediaType)
        case .url(let url, _):
            let blob = try await downloadBlob(url: url,
                headers: withUserAgentSuffix(nil, "ai-sdk-openai/\(OPENAI_VERSION)"), isAborted: abortSignal)
            return .data(blob.data, contentType: blob.mediaType)
        }
    }

    private func metadata(_ response: OpenAIImageResponse) -> [JSONValue] {
        response.data.enumerated().map { index, item in
            var entry: JSONObject = [:]
            if let prompt = item.revisedPrompt, !prompt.isEmpty { entry["revisedPrompt"] = .string(prompt) }
            if let created = response.created { entry["created"] = .number(created) }
            if let size = response.size { entry["size"] = .string(size) }
            if let quality = response.quality { entry["quality"] = .string(quality) }
            if let background = response.background { entry["background"] = .string(background) }
            if let format = response.outputFormat { entry["outputFormat"] = .string(format) }
            func share(_ count: Int) -> JSONValue {
                let base = floor(Double(count) / Double(response.data.count))
                return .number(index == response.data.count - 1 ? Double(count) - base * Double(response.data.count - 1) : base)
            }
            if let count = response.usage?.inputTokensDetails?.imageTokens { entry["imageTokens"] = share(count) }
            if let count = response.usage?.inputTokensDetails?.textTokens { entry["textTokens"] = share(count) }
            return .object(entry)
        }
    }
}
