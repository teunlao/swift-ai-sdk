import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AzureMaiImageConfig: Sendable {
    public let url: @Sendable (String) throws -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public let _internal: Internal?

    public struct Internal: Sendable {
        public let currentDate: (@Sendable () -> Date)?
        public init(currentDate: (@Sendable () -> Date)? = nil) { self.currentDate = currentDate }
    }

    public init(url: @escaping @Sendable (String) throws -> String,
                headers: @escaping @Sendable () throws -> [String: String?],
                fetch: FetchFunction? = nil, _internal: Internal? = nil) {
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self._internal = _internal
    }
}

public final class AzureMaiImageModel: ImageModelV4 {
    public let modelId: String
    public let provider = "azure.image"
    public let maxImagesPerCall: ImageModelV4MaxImagesPerCall = .value(1)
    public let supportsFileInputs: Bool? = true
    public let supportsMaskInputs: Bool? = false
    private let config: AzureMaiImageConfig

    public init(modelId: String, config: AzureMaiImageConfig) {
        self.modelId = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        try await doGenerate(options: options, maiOptions: .init())
    }

    public func doGenerate(options: ImageModelV4CallOptions, maiOptions: AzureImageModelMaiOptions) async throws -> ImageModelV4GenerateResult {
        let timestamp = config._internal?.currentDate?() ?? Date()
        var warnings: [SharedV4Warning] = []
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
        if options.mask != nil {
            warnings.append(.unsupported(feature: "mask", details: "MAI image edits do not support masks."))
        }
        var dimensions = options.size.map(Dimensions.init(size:))
        if options.size != nil && options.aspectRatio != nil {
            warnings.append(.unsupported(feature: "aspectRatio", details: "aspectRatio is ignored when size is set."))
        } else if let ratio = options.aspectRatio {
            dimensions = Dimensions(aspectRatio: ratio)
            if dimensions == nil {
                warnings.append(.unsupported(feature: "aspectRatio", details: "Invalid aspect ratio: \(ratio)."))
            }
        }
        var fields: [(String, Field)] = [("model", .string(modelId))]
        if let prompt = options.prompt { fields.append(("prompt", .string(prompt))) }
        if let dimensions {
            fields.append(("width", .number(dimensions.width)))
            fields.append(("height", .number(dimensions.height)))
        }
        if let value = maiOptions.autoAspectRatio { fields.append(("auto_aspect_ratio", .bool(value))) }
        if let value = maiOptions.webGrounding { fields.append(("web_grounding", .bool(value))) }
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }
        let images: [DownloadedBlob]?
        if let files = options.files, !files.isEmpty { images = try await blobs(files, abortSignal: options.abortSignal) }
        else { images = nil }
        let form: MultipartFormDataBuilder?
        if let images {
            var builder = MultipartFormDataBuilder()
            for (key, value) in fields {
                builder.appendField(name: key, value: try value.formValue())
            }
            for (index, image) in images.enumerated() {
                builder.appendFile(name: "image", filename: "image-\(index + 1).\(image.mediaType?.lowercased() == "image/jpeg" ? "jpg" : "png")",
                    contentType: image.mediaType, data: image.data)
            }
            form = builder
        } else { form = nil }
        let body = JSONValue.object(Dictionary(uniqueKeysWithValues: fields.map { ($0.0, $0.1.json) }))
        let responses = try await withThrowingTaskGroup(of: IndexedResponse.self) { group in
            for index in 0..<max(1, options.n) {
                group.addTask {
                    let response: ResponseHandlerResult<MaiResponse>
                    if let form {
                        response = try await postToAPI(url: self.config.url("/images/edits"), headers: headers,
                            body: .init(content: .multipartFormData(form), values: form.values),
                            failedResponseHandler: maiFailedResponseHandler,
                            successfulResponseHandler: createJsonResponseHandler(responseSchema: maiResponseSchema),
                            isAborted: options.abortSignal, fetch: self.config.fetch)
                    } else {
                        response = try await postJsonToAPI(url: self.config.url("/images/generations"), headers: headers, body: body,
                            failedResponseHandler: maiFailedResponseHandler,
                            successfulResponseHandler: createJsonResponseHandler(responseSchema: maiResponseSchema),
                            isAborted: options.abortSignal, fetch: self.config.fetch)
                    }
                    return .init(index: index, response: response)
                }
            }
            var responses: [IndexedResponse] = []
            for try await response in group { responses.append(response) }
            return responses.sorted { $0.index < $1.index }.map(\.response)
        }
        var usage: ImageModelV4Usage?
        var metadata: [JSONValue] = []
        for response in responses {
            let value = response.value
            if let counts = value.usage {
                let input = try addTokens(counts.text, counts.image)
                usage = try .init(inputTokens: addTokens(usage?.inputTokens, input),
                    outputTokens: addTokens(usage?.outputTokens, counts.output),
                    totalTokens: addTokens(usage?.totalTokens, addTokens(input, counts.output)))
            }
            var entry: JSONObject = [:]
            if let created = value.created { entry["created"] = .number(created) }
            if let size = value.size { entry["size"] = .string(size) }
            if let count = value.usage?.text { entry["textTokens"] = .number(Double(count)) }
            if let count = value.usage?.image { entry["imageTokens"] = .number(Double(count)) }
            metadata.append(contentsOf: value.data.map { _ in .object(entry) })
        }
        return .init(images: .base64(responses.flatMap { $0.value.data.map(\.b64JSON) }), warnings: warnings,
            providerMetadata: ["azure": .init(images: metadata)],
            response: .init(timestamp: timestamp, modelId: modelId, headers: responses.first?.responseHeaders), usage: usage)
    }

    private enum Field: Sendable {
        case string(String), number(Double), bool(Bool)

        var json: JSONValue {
            switch self {
            case .string(let value): return .string(value)
            case .bool(let value): return .bool(value)
            case .number(let value): return value.isFinite ? .number(value) : .null
            }
        }

        func formValue() throws -> String {
            switch self {
            case .string(let value): return value
            case .bool(let value): return String(value)
            case .number(let value):
                if value.isNaN { return "NaN" }
                if value == .infinity { return "Infinity" }
                if value == -.infinity { return "-Infinity" }
                if value == 0 { return "0" }
                return String(decoding: try JSONEncoder().encode(JSONValue.number(value)), as: UTF8.self)
            }
        }
    }

    private struct IndexedResponse: Sendable {
        let index: Int
        let response: ResponseHandlerResult<MaiResponse>
    }

    private struct IndexedBlob: Sendable {
        let index: Int
        let blob: DownloadedBlob
    }

    private func blobs(_ files: [ImageModelV4File], abortSignal: (@Sendable () -> Bool)?) async throws -> [DownloadedBlob] {
        try await withThrowingTaskGroup(of: IndexedBlob.self) { group in
            for (index, file) in files.enumerated() {
                group.addTask {
                    let blob: DownloadedBlob
                    switch file {
                    case .url(let url, _):
                        blob = try await downloadBlob(url: url, headers: withUserAgentSuffix(nil, "ai-sdk-azure/\(AZURE_PROVIDER_VERSION)"),
                            isAborted: abortSignal)
                    case .file(let mediaType, let data, _):
                        let bytes: Data
                        switch data {
                        case .binary(let binary): bytes = binary
                        case .base64(let base64): bytes = try convertBase64ToData(base64)
                        }
                        let type = mediaType.utf8.allSatisfy { (0x20...0x7E).contains($0) } ? mediaType.lowercased() : ""
                        blob = .init(data: bytes, mediaType: type)
                    }
                    return .init(index: index, blob: blob)
                }
            }
            var blobs: [IndexedBlob] = []
            for try await blob in group { blobs.append(blob) }
            return blobs.sorted { $0.index < $1.index }.map(\.blob)
        }
    }
}

private func addTokens(_ first: Int?, _ second: Int?) throws -> Int? {
    if first == nil && second == nil { return nil }
    let sum = (first ?? 0).addingReportingOverflow(second ?? 0)
    guard !sum.overflow else {
        throw InvalidResponseDataError(data: [first, second], message: "MAI token usage exceeds the integer range.")
    }
    return sum.partialValue
}

private struct Dimensions {
    let width: Double
    let height: Double

    init(size: String) {
        let parts = size.components(separatedBy: "x")
        width = Self.number(parts.first ?? "")
        height = parts.dropFirst().first.map(Self.number) ?? .nan
    }

    init?(aspectRatio: String) {
        let parts = aspectRatio.components(separatedBy: ":")
        let w = Self.number(parts.first ?? "")
        let h = parts.dropFirst().first.map(Self.number) ?? .nan
        guard w > 0, h > 0 else { return nil }
        let ratio = w / h
        var width = sqrt(1024 * 1024 * ratio)
        var height = width / ratio
        if min(width, height) < 768 {
            (width, height) = width < height ? (768, 768 / ratio) : (768 * ratio, 768)
        }
        self.width = max(768, floor(width / 16 + 1e-9) * 16)
        self.height = max(768, floor(height / 16 + 1e-9) * 16)
    }

    private static func number(_ value: String) -> Double {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? 0 : Double(text) ?? .nan
    }
}

private struct MaiResponse: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let b64JSON: String
        enum CodingKeys: String, CodingKey { case b64JSON = "b64_json" }
    }
    struct Usage: Decodable, Sendable {
        let text: Int?
        let image: Int?
        let output: Int?
        enum CodingKeys: String, CodingKey {
            case text = "num_input_text_tokens", image = "num_input_image_tokens", output = "num_output_tokens"
        }
    }
    let created: Double?
    let size: String?
    let usage: Usage?
    let data: [Item]
}

private struct MaiError: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let code: JSONValue?
        let message: String
        enum CodingKeys: String, CodingKey { case code, message }
        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            code = try fields.decodeIfPresent(JSONValue.self, forKey: .code)
            if let code {
                switch code {
                case .string, .number: break
                default: throw DecodingError.dataCorruptedError(forKey: .code, in: fields, debugDescription: "Expected string or numeric error code")
                }
            }
            message = try fields.decode(String.self, forKey: .message)
        }
    }
    let error: Detail
}

private let maiResponseSchema = FlexibleSchema(Schema.codable(MaiResponse.self, jsonSchema: [
    "type": "object", "required": ["data"], "properties": [
        "created": ["type": ["number", "null"]], "size": ["type": ["string", "null"]],
        "data": ["type": "array", "items": ["type": "object", "required": ["b64_json"], "properties": ["b64_json": ["type": "string"]]]],
        "usage": ["type": ["object", "null"], "properties": [
            "num_input_text_tokens": ["type": ["integer", "null"]],
            "num_input_image_tokens": ["type": ["integer", "null"]],
            "num_output_tokens": ["type": ["integer", "null"]]
        ]]
    ]
]))

private let maiFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema.codable(MaiError.self, jsonSchema: [
        "type": "object", "required": ["error"], "properties": [
            "error": ["type": "object", "required": ["message"], "properties": [
                "code": ["type": ["string", "number", "null"]], "message": ["type": "string"]
            ]]
        ]
    ])), errorToMessage: { $0.error.message }
)
