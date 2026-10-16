import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleImageModelConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () throws -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) throws -> String
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let currentDate: @Sendable () -> Date

    public init(provider: String, headers: @escaping @Sendable () throws -> [String: String] = { [:] },
                url: @escaping @Sendable (OpenAICompatibleURLOptions) throws -> String, fetch: FetchFunction? = nil,
                errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
                currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.headers = headers; self.url = url; self.fetch = fetch
        self.errorConfiguration = errorConfiguration; self.currentDate = currentDate
    }
}

public final class OpenAICompatibleImageModel: ImageModelV4 {
    public let specificationVersion = "v4"
    public let modelId: String
    public var provider: String { config.provider }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(10) }
    private let config: OpenAICompatibleImageModelConfig
    public init(modelId: OpenAICompatibleImageModelId, config: OpenAICompatibleImageModelConfig) {
        self.modelId = modelId.rawValue; self.config = config
    }
    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []
        if options.aspectRatio != nil { warnings.append(.unsupported(feature: "aspectRatio", details: "This model does not support aspect ratio. Use `size` instead.")) }
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
        let timestamp = config.currentDate()
        let key = provider.split(separator: ".").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if let warning = openAICompatibleDeprecatedProviderOptionsWarning(rawName: key, providerOptions: options.providerOptions) { warnings.append(warning) }
        var arguments = options.providerOptions?[key] ?? [:]
        arguments.merge(options.providerOptions?[openAICompatibleCamelCase(key)] ?? [:]) { _, new in new }
        let editing = !(options.files?.isEmpty ?? true)
        let url = try config.url(.init(modelId: modelId, path: editing ? "/images/edits" : "/images/generations"))
        let headers = combineHeaders(try config.headers().mapValues(Optional.some), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }
        let response: ResponseHandlerResult<CompatibleImageResponse>
        if editing {
            var images: [FormDataValue] = []
            for file in options.files ?? [] { images.append(try await blob(file)) }
            var form: [String: FormDataInputValue?] = [
                "model": .value(.string(modelId)), "prompt": options.prompt.map { .value(.string($0)) },
                "image": .array(images), "n": .value(.string(String(options.n))), "size": options.size.map { .value(.string($0)) }
            ]
            if let mask = options.mask { form["mask"] = .value(try await blob(mask)) }
            for (key, value) in arguments {
                switch value {
                case .null: form[key] = nil
                case .array(let values): form[key] = .array(values.map { .string(formString($0)) })
                default: form[key] = .value(.string(formString(value)))
                }
            }
            response = try await postToAPI(url: url, headers: headers,
                                            body: .init(content: .multipartFormData(convertToFormData(form)), values: nil),
                                            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                                            successfulResponseHandler: createJsonResponseHandler(responseSchema: compatibleImageResponseSchema),
                                            isAborted: options.abortSignal, fetch: config.fetch)
        } else {
            var body: [String: JSONValue] = ["model": .string(modelId), "n": .number(Double(options.n))]
            if let prompt = options.prompt { body["prompt"] = .string(prompt) }
            if let size = options.size { body["size"] = .string(size) }
            body.merge(arguments) { _, new in new }
            response = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body),
                                               failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                                               successfulResponseHandler: createJsonResponseHandler(responseSchema: compatibleImageResponseSchema),
                                               isAborted: options.abortSignal, fetch: config.fetch)
        }
        let images: ImageModelV4GeneratedImages
        if response.value.data.allSatisfy({ $0.base64 != nil }) {
            images = .base64(response.value.data.compactMap(\.base64))
        } else {
            var values: [Data] = []
            for item in response.value.data {
                if let base64 = item.base64 { values.append(try convertBase64ToData(base64)) }
                else if let imageURL = item.url {
                    let download = try await getFromAPI(url: imageURL, headers: headers,
                                                         failedResponseHandler: createStatusCodeErrorResponseHandler(),
                                                         successfulResponseHandler: createBinaryResponseHandler(),
                                                         isAborted: options.abortSignal, fetch: config.fetch,
                                                         validateUrl: true, credentialedOrigin: url, trustedOrigin: url)
                    values.append(download.value)
                }
            }
            images = .binary(values)
        }
        let usage = response.value.usage.map { ImageModelV4Usage(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, totalTokens: $0.totalTokens) }
        return .init(images: images, warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders), usage: usage)
    }
    private func blob(_ file: ImageModelV4File) async throws -> FormDataValue {
        switch file {
        case .url(let url, _):
            let value = try await downloadBlob(url: url)
            return .data(value.data, filename: "blob", contentType: value.mediaType)
        case .file(let mediaType, let data, _):
            let bytes: Data
            switch data {
            case .binary(let value): bytes = value
            case .base64(let value): bytes = try convertBase64ToData(value)
            }
            return .data(bytes, filename: "blob", contentType: mediaType)
        }
    }
    private func formString(_ value: JSONValue, insideArray: Bool = false) -> String {
        switch value {
        case .null: return insideArray ? "" : "null"
        case .string(let text): return text
        case .number(let number): return Int(exactly: number).map(String.init) ?? String(number)
        case .bool(let boolean): return boolean ? "true" : "false"
        case .array(let array): return array.map { formString($0, insideArray: true) }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }
}

private struct CompatibleImageResponse: Decodable, Sendable {
    struct Image: Decodable, Sendable {
        let base64: String?
        let url: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            base64 = try c.decodeIfPresent(String.self, forKey: .base64)
            url = try c.decodeIfPresent(String.self, forKey: .url)
            guard base64 != nil || url != nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected b64_json or url in the image response"))
            }
        }
        private enum Key: String, CodingKey { case base64 = "b64_json", url }
    }
    struct Usage: Decodable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens", outputTokens = "output_tokens", totalTokens = "total_tokens" }
    }
    let data: [Image]
    let usage: Usage?
}
private let compatibleImageResponseSchema = FlexibleSchema(Schema<CompatibleImageResponse>.codable(CompatibleImageResponse.self, jsonSchema: ["type": "object"]))
