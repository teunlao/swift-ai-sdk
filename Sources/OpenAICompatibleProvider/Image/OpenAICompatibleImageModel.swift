import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleImageModelConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.currentDate = currentDate
    }
}

private enum OpenAICompatibleImageContract: Sendable, Equatable {
    case v3
    case v4
}

private struct OpenAICompatibleImageCoreResult: Sendable {
    let images: [String]
    let warnings: [SharedV4Warning]
    let timestamp: Date
    let responseHeaders: SharedV4Headers?
}

private struct OpenAICompatibleImageModelCore: Sendable {
    private let modelIdentifier: OpenAICompatibleImageModelId
    private let config: OpenAICompatibleImageModelConfig
    private let v4ProviderOptionsName: String

    init(modelId: OpenAICompatibleImageModelId, config: OpenAICompatibleImageModelConfig) {
        modelIdentifier = modelId
        self.config = config
        v4ProviderOptionsName = config.provider
            .split(separator: ".", omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    func doGenerate(
        prompt: String?,
        n: Int,
        size: String?,
        aspectRatio: String?,
        seed: Int?,
        files: [ImageModelV4File]?,
        mask: ImageModelV4File?,
        providerOptions: SharedV4ProviderOptions?,
        abortSignal: (@Sendable () -> Bool)?,
        requestHeaders: SharedV4Headers?,
        contract: OpenAICompatibleImageContract
    ) async throws -> OpenAICompatibleImageCoreResult {
        var warnings = makeUnsupportedSettingWarnings(
            aspectRatio: aspectRatio,
            seed: seed
        )
        let requestTimestamp = contract == .v4 ? config.currentDate() : nil
        let providerArguments = providerArguments(
            providerOptions: providerOptions,
            contract: contract,
            warnings: &warnings
        )
        let headers = combineHeaders(
            config.headers().mapValues { Optional($0) },
            requestHeaders?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response: ResponseHandlerResult<OpenAICompatibleImageResponse>
        if contract == .v4, let files, !files.isEmpty {
            let formData = try await makeEditFormData(
                prompt: prompt,
                n: n,
                size: size,
                files: files,
                mask: mask,
                providerArguments: providerArguments
            )
            response = try await postToAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/edits")),
                headers: headers,
                body: PostBody(
                    content: .multipartFormData(convertToFormData(formData)),
                    values: formData
                ),
                failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(
                    responseSchema: openAICompatibleImageResponseSchema
                ),
                isAborted: abortSignal,
                fetch: config.fetch
            )
        } else {
            let body = makeGenerationBody(
                prompt: prompt,
                n: n,
                size: size,
                providerArguments: providerArguments,
                contract: contract
            )
            response = try await postJsonToAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/generations")),
                headers: headers,
                body: JSONValue.object(body),
                failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(
                    responseSchema: openAICompatibleImageResponseSchema
                ),
                isAborted: abortSignal,
                fetch: config.fetch
            )
        }

        return OpenAICompatibleImageCoreResult(
            images: response.value.data.map(\.b64JSON),
            warnings: warnings,
            timestamp: requestTimestamp ?? config.currentDate(),
            responseHeaders: response.responseHeaders
        )
    }

    private func makeUnsupportedSettingWarnings(
        aspectRatio: String?,
        seed: Int?
    ) -> [SharedV4Warning] {
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
        return warnings
    }

    private func providerArguments(
        providerOptions: SharedV4ProviderOptions?,
        contract: OpenAICompatibleImageContract,
        warnings: inout [SharedV4Warning]
    ) -> [String: JSONValue] {
        switch contract {
        case .v3:
            return providerOptions?["openai"] ?? [:]

        case .v4:
            if let warning = openAICompatibleDeprecatedProviderOptionsWarning(
                rawName: v4ProviderOptionsName,
                providerOptions: providerOptions
            ) {
                warnings.append(warning)
            }

            var arguments = providerOptions?[v4ProviderOptionsName] ?? [:]
            let camelCaseName = openAICompatibleCamelCase(v4ProviderOptionsName)
            for (key, value) in providerOptions?[camelCaseName] ?? [:] {
                arguments[key] = value
            }
            return arguments
        }
    }

    private func makeGenerationBody(
        prompt: String?,
        n: Int,
        size: String?,
        providerArguments: [String: JSONValue],
        contract: OpenAICompatibleImageContract
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "n": .number(Double(n)),
            "response_format": .string("b64_json")
        ]
        if let prompt {
            body["prompt"] = .string(prompt)
        }
        if let size {
            body["size"] = .string(size)
        }

        for (key, value) in providerArguments {
            body[key] = value
        }
        // V3 allowed provider options to replace this default; V4 makes the upstream field authoritative.
        if contract == .v4 {
            body["response_format"] = .string("b64_json")
        }
        return body
    }

    private func makeEditFormData(
        prompt: String?,
        n: Int,
        size: String?,
        files: [ImageModelV4File],
        mask: ImageModelV4File?,
        providerArguments: [String: JSONValue]
    ) async throws -> [String: FormDataInputValue?] {
        let imageValues = try await formDataValues(for: files)

        let maskValue: FormDataInputValue?
        if let mask {
            maskValue = .value(try await formDataValue(for: mask))
        } else {
            maskValue = nil
        }

        var formData: [String: FormDataInputValue?] = [
            "model": .value(.string(modelIdentifier.rawValue)),
            "prompt": prompt.map { .value(.string($0)) },
            "image": .array(imageValues),
            "mask": maskValue,
            "n": .value(.string(String(n))),
            "size": size.map { .value(.string($0)) }
        ]

        for (key, value) in providerArguments {
            formData[key] = formDataInputValue(from: value)
        }
        return formData
    }

    private func formDataValue(for file: ImageModelV4File) async throws -> FormDataValue {
        switch file {
        case let .file(mediaType, data, _):
            let bytes: Data
            switch data {
            case .base64(let base64):
                bytes = try convertBase64ToData(base64)
            case .binary(let data):
                bytes = data
            }
            return .data(bytes, filename: "blob", contentType: mediaType)

        case .url(let url, _):
            let blob = try await downloadBlob(url: url)
            return .data(blob.data, filename: "blob", contentType: blob.mediaType)
        }
    }

    private func formDataValues(for files: [ImageModelV4File]) async throws -> [FormDataValue] {
        try await withThrowingTaskGroup(
            of: (Int, FormDataValue).self,
            returning: [FormDataValue].self
        ) { group in
            for (index, file) in files.enumerated() {
                group.addTask {
                    (index, try await formDataValue(for: file))
                }
            }

            var indexedValues: [(Int, FormDataValue)] = []
            indexedValues.reserveCapacity(files.count)
            for try await value in group {
                indexedValues.append(value)
            }
            return indexedValues.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func formDataInputValue(from value: JSONValue) -> FormDataInputValue? {
        switch value {
        case .null:
            return nil
        case .array(let values):
            return .array(values.map { .string(javaScriptString(from: $0)) })
        default:
            return .value(.string(javaScriptString(from: value)))
        }
    }

    private func javaScriptString(from value: JSONValue) -> String {
        // Upstream FormData.append coerces every non-Blob provider option using JavaScript string semantics.
        switch value {
        case .null:
            return "null"
        case .string(let string):
            return string
        case .number(let number):
            if let integer = Int(exactly: number) {
                return String(integer)
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array(let values):
            return values.map(javaScriptString(from:)).joined(separator: ",")
        case .object:
            return "[object Object]"
        }
    }
}

public final class OpenAICompatibleImageModel: ImageModelV3 {
    public let specificationVersion = "v3"
    public let modelIdentifier: OpenAICompatibleImageModelId
    private let core: OpenAICompatibleImageModelCore

    public init(modelId: OpenAICompatibleImageModelId, config: OpenAICompatibleImageModelConfig) {
        modelIdentifier = modelId
        core = OpenAICompatibleImageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(10) }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        // The preserved V3 contract only owns JSON generation; editing is a native V4 transport surface.
        let result = try await core.doGenerate(
            prompt: options.prompt,
            n: options.n,
            size: options.size,
            aspectRatio: options.aspectRatio,
            seed: options.seed,
            files: nil,
            mask: nil,
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            requestHeaders: options.headers,
            contract: .v3
        )

        return ImageModelV3GenerateResult(
            images: .base64(result.images),
            warnings: result.warnings.map(convertSharedV4WarningToV3),
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
                timestamp: result.timestamp,
                modelId: modelIdentifier.rawValue,
                headers: result.responseHeaders
            )
        )
    }
}

public final class OpenAICompatibleImageModelV4: ImageModelV4 {
    public let specificationVersion = "v4"
    public let modelIdentifier: OpenAICompatibleImageModelId
    private let core: OpenAICompatibleImageModelCore

    public init(modelId: OpenAICompatibleImageModelId, config: OpenAICompatibleImageModelConfig) {
        modelIdentifier = modelId
        core = OpenAICompatibleImageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(10) }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let result = try await core.doGenerate(
            prompt: options.prompt,
            n: options.n,
            size: options.size,
            aspectRatio: options.aspectRatio,
            seed: options.seed,
            files: options.files,
            mask: options.mask,
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            requestHeaders: options.headers,
            contract: .v4
        )

        return ImageModelV4GenerateResult(
            images: .base64(result.images),
            warnings: result.warnings,
            response: ImageModelV4ResponseInfo(
                timestamp: result.timestamp,
                modelId: modelIdentifier.rawValue,
                headers: result.responseHeaders
            )
        )
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private struct OpenAICompatibleImageResponse: Codable {
    struct DataItem: Codable {
        let b64JSON: String

        private enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [DataItem]
}

private let openAICompatibleImageResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleImageResponse>.codable(
        OpenAICompatibleImageResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
