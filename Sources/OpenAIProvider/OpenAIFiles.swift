import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIFilesConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

public struct OpenAIFilesOptions: Sendable, Equatable {
    public var purpose: String?
    public var expiresAfter: Double?

    public init(purpose: String? = nil, expiresAfter: Double? = nil) {
        self.purpose = purpose
        self.expiresAfter = expiresAfter
    }
}

private let openAIFilesOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "purpose": .object(["type": .string("string")]),
        "expiresAfter": .object(["type": .string("number")])
    ]),
    "additionalProperties": .bool(true)
])

let openAIFilesOptionsSchema = FlexibleSchema<OpenAIFilesOptions>(
    Schema(
        jsonSchemaResolver: { openAIFilesOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }
                var options = OpenAIFilesOptions()
                if let purposeValue = dict["purpose"] {
                    guard case .string(let purpose) = purposeValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "purpose must be a string")
                        return .failure(error: TypeValidationError.wrap(value: purposeValue, cause: error))
                    }
                    options.purpose = purpose
                }
                if let expiresAfterValue = dict["expiresAfter"] {
                    guard case .number(let expiresAfter) = expiresAfterValue, expiresAfter.isFinite else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "expiresAfter must be a finite number")
                        return .failure(error: TypeValidationError.wrap(value: expiresAfterValue, cause: error))
                    }
                    options.expiresAfter = expiresAfter
                }
                return .success(value: options)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct OpenAIFileResponse: Codable, Sendable {
    let id: String
    let object: String?
    let bytes: Double?
    let createdAt: Double?
    let filename: String?
    let purpose: String?
    let status: String?
    let expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, object, bytes, filename, purpose, status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

private let openAIFileResponseSchema = FlexibleSchema(
    Schema<OpenAIFileResponse>.codable(
        OpenAIFileResponse.self,
        jsonSchema: [
            "type": "object", "required": ["id"],
            "properties": [
                "id": ["type": "string"],
                "object": ["type": ["string", "null"]],
                "bytes": ["type": ["number", "null"]],
                "created_at": ["type": ["number", "null"]],
                "filename": ["type": ["string", "null"]],
                "purpose": ["type": ["string", "null"]],
                "status": ["type": ["string", "null"]],
                "expires_at": ["type": ["number", "null"]]
            ]
        ]
    )
)

private struct OpenAIFileDeleteResponse: Codable, Sendable {
    let id: String
    let object: String?
    let deleted: Bool
}

private let openAIFileDeleteResponseSchema = FlexibleSchema(
    Schema<OpenAIFileDeleteResponse>.codable(
        OpenAIFileDeleteResponse.self,
        jsonSchema: [
            "type": "object", "required": ["id", "deleted"],
            "properties": [
                "id": ["type": "string"],
                "object": ["type": ["string", "null"]],
                "deleted": ["type": "boolean"]
            ]
        ]
    )
)

public final class OpenAIFiles: FilesV4MetadataReader, FilesV4Downloader, FilesV4Deleter {
    public let specificationVersion = "v4"
    public var provider: String { config.provider }

    private let config: OpenAIFilesConfig

    init(config: OpenAIFilesConfig) {
        self.config = config
    }

    public func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        let openAIOptions: OpenAIFilesOptions?
        let headers: [String: String?]
        do {
            openAIOptions = try await parseProviderOptions(
                provider: "openai", providerOptions: options.providerOptions, schema: openAIFilesOptionsSchema
            )
            headers = try requestHeaders(options.headers)
        } catch {
            if case .stream(let stream) = options.data { await cancelStream(stream) }
            throw error
        }

        let purpose = openAIOptions?.purpose ?? "assistants"
        let response: OpenAIFileResponse
        let url = "\(config.baseURL)/files"
        if case .stream(let stream) = options.data {
            var parts: [MultipartStreamPart] = [.field(name: "purpose", value: purpose)]
            if let expiry = openAIOptions?.expiresAfter {
                parts.append(.field(name: "expires_after[anchor]", value: "created_at"))
                parts.append(.field(name: "expires_after[seconds]", value: jsNumberString(expiry)))
            }
            parts.append(.file(name: "file", filename: options.filename, mediaType: options.mediaType, content: .stream(stream)))
            response = try await postMultipartStreamToAPI(
                url: url, headers: headers, parts: parts,
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIFileResponseSchema),
                isAborted: options.abortSignal, fetch: config.fetch
            ).value
        } else {
            let data = try convertInlineFileDataToData(options.data)
            var builder = MultipartFormDataBuilder()
            builder.appendFile(name: "file", filename: options.filename, contentType: options.mediaType, data: data)
            builder.appendField(name: "purpose", value: purpose)
            var values: [String: Any] = ["file": data, "purpose": purpose]
            if let expiry = openAIOptions?.expiresAfter {
                let seconds = jsNumberString(expiry)
                builder.appendField(name: "expires_after[anchor]", value: "created_at")
                builder.appendField(name: "expires_after[seconds]", value: seconds)
                values["expires_after[anchor]"] = "created_at"
                values["expires_after[seconds]"] = seconds
            }
            response = try await postToAPI(
                url: url, headers: headers.compactMapValues { $0 },
                body: PostBody(content: .multipartFormData(builder), values: values),
                failedResponseHandler: openAIFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIFileResponseSchema),
                isAborted: options.abortSignal, fetch: config.fetch
            ).value
        }

        let filename = response.filename ?? options.filename
        return FilesV4UploadFileResult(
            providerReference: ["openai": response.id],
            mediaType: options.mediaType,
            filename: filename.flatMap { $0.isEmpty ? nil : $0 },
            byteSize: response.bytes,
            createdAt: response.createdAt.map(Date.init(timeIntervalSince1970:)),
            expiresAt: response.expiresAt.map(Date.init(timeIntervalSince1970:)),
            providerMetadata: ["openai": metadata(response)]
        )
    }

    public func getFileMetadata(options: FilesV4GetFileMetadataCallOptions) async throws -> FilesV4GetFileMetadataResult {
        let response = try await getFromAPI(
            url: try fileURL(options.file),
            headers: try requestHeaders(options.headers).compactMapValues { $0 },
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIFileResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch, validateUrl: false
        ).value
        return FilesV4GetFileMetadataResult(
            providerReference: ["openai": response.id],
            filename: response.filename,
            byteSize: response.bytes,
            createdAt: response.createdAt.map(Date.init(timeIntervalSince1970:)),
            expiresAt: response.expiresAt.map(Date.init(timeIntervalSince1970:)),
            providerMetadata: ["openai": metadata(response)]
        )
    }

    public func downloadFile(options: FilesV4DownloadFileCallOptions) async throws -> FilesV4DownloadFileResult {
        let response = try await getFromAPI(
            url: "\(try fileURL(options.file))/content",
            headers: try requestHeaders(options.headers).compactMapValues { $0 },
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createBinaryStreamResponseHandler(),
            isAborted: options.abortSignal, fetch: config.fetch, validateUrl: false
        )
        let mediaType = response.responseHeaders["content-type"]?
            .components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FilesV4DownloadFileResult(content: response.value, mediaType: mediaType.flatMap { $0.isEmpty ? nil : $0 })
    }

    public func deleteFile(options: FilesV4DeleteFileCallOptions) async throws -> FilesV4DeleteFileResult {
        let response = try await deleteFromAPI(
            url: try fileURL(options.file), headers: try requestHeaders(options.headers),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIFileDeleteResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        ).value
        return FilesV4DeleteFileResult(providerReference: ["openai": response.id], deleted: response.deleted)
    }

    private func requestHeaders(_ headers: SharedV4Headers?) throws -> [String: String?] {
        combineHeaders(try config.headers(), headers?.mapValues { Optional($0) })
    }

    private func fileURL(_ reference: SharedV4ProviderReference) throws -> String {
        let whitespace = CharacterSet(charactersIn: "\u{9}\u{a}\u{b}\u{c}\u{d} \u{a0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200a}\u{2028}\u{2029}\u{202f}\u{205f}\u{3000}\u{feff}")
        guard let id = reference["openai"], !id.trimmingCharacters(in: whitespace).isEmpty else {
            throw InvalidArgumentError(argument: "file", message: "file reference is missing an 'openai' file id.")
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed)!
        // URL parsers normalize both literal and single-encoded dot segments.
        let segment = encoded == "." ? "%252E" : encoded == ".." ? "%252E%252E" : encoded
        return "\(config.baseURL)/files/\(segment)"
    }

    private func metadata(_ response: OpenAIFileResponse) -> JSONObject {
        var value: JSONObject = [:]
        if let filename = response.filename { value["filename"] = .string(filename) }
        if let purpose = response.purpose { value["purpose"] = .string(purpose) }
        if let bytes = response.bytes { value["bytes"] = .number(bytes) }
        if let createdAt = response.createdAt { value["createdAt"] = .number(createdAt) }
        if let status = response.status { value["status"] = .string(status) }
        if let expiresAt = response.expiresAt { value["expiresAt"] = .number(expiresAt) }
        return value
    }
}
