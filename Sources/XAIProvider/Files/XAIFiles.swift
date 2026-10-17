import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIFilesOptions: Codable, Sendable, Equatable {
    public var teamId: String?
    public var filePath: String?
    public var expiresAfter: Int?
    public init(teamId: String? = nil, filePath: String? = nil, expiresAfter: Int? = nil) { self.teamId = teamId; self.filePath = filePath; self.expiresAfter = expiresAfter }
}

private let filesOptionsSchema = FlexibleSchema(Schema<XAIFilesOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        guard case .object(let object) = json else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected an object") }
        for key in ["teamId", "filePath", "expiresAfter"] where object[key] == .null { throw InvalidArgumentError(argument: key, message: "Expected a non-null option") }
        let options = try JSONDecoder().decode(XAIFilesOptions.self, from: JSONEncoder().encode(json))
        if let expiry = options.expiresAfter, !(3600...2_592_000).contains(expiry) { throw InvalidArgumentError(argument: "expiresAfter", message: "Expected 3600 to 2592000 seconds") }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

struct XAIFilesConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

private struct FileResponse: Codable, Sendable {
    let id: String
    let object: String?
    let bytes: Double?
    let createdAt: Double?
    let expiresAt: Double?
    let filename: String?
    let purpose: String?
    let status: String?
    enum CodingKeys: String, CodingKey { case id, object, bytes, createdAt = "created_at", expiresAt = "expires_at", filename, purpose, status }
    var metadata: SharedV4ProviderMetadata {
        var fields: [String: JSONValue] = [:]
        if let filename { fields["filename"] = .string(filename) }
        if let purpose { fields["purpose"] = .string(purpose) }
        if let bytes { fields["bytes"] = .number(bytes) }
        if let createdAt { fields["createdAt"] = .number(createdAt) }
        if let expiresAt { fields["expiresAt"] = .number(expiresAt) }
        if let status { fields["status"] = .string(status) }
        return ["xai": fields]
    }
}
private struct DeleteResponse: Codable, Sendable { let id: String; let object: String?; let deleted: Bool }
private let fileResponseSchema = FlexibleSchema(Schema<FileResponse>.codable(FileResponse.self, jsonSchema: .object(["type": .string("object")])))
private let deleteResponseSchema = FlexibleSchema(Schema<DeleteResponse>.codable(DeleteResponse.self, jsonSchema: .object(["type": .string("object")])))

public final class XAIFiles: FilesV4MetadataReader, FilesV4Downloader, FilesV4Deleter {
    public let specificationVersion = "v4"
    public var provider: String { config.provider }
    private let config: XAIFilesConfig
    init(config: XAIFilesConfig) { self.config = config }

    public func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        let xai: XAIFilesOptions?
        do { xai = try await parseProviderOptions(provider: "xai", providerOptions: options.providerOptions, schema: filesOptionsSchema) }
        catch {
            if case .stream(let stream) = options.data { await cancelStream(stream) }
            throw error
        }
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some))
        let response: FileResponse
        if case .stream(let stream) = options.data {
            var parts: [MultipartStreamPart] = []
            if let expiry = xai?.expiresAfter { parts.append(.field(name: "expires_after", value: String(expiry))) }
            if let team = xai?.teamId { parts.append(.field(name: "team_id", value: team)) }
            parts.append(.file(name: "file", filename: options.filename, mediaType: options.mediaType, content: .stream(stream)))
            response = try await postMultipartStreamToAPI(url: "\(config.baseURL)/files", headers: headers, parts: parts, failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: fileResponseSchema), isAborted: options.abortSignal, fetch: config.fetch).value
        } else {
            var multipart = MultipartFormDataBuilder()
            if let expiry = xai?.expiresAfter { multipart.appendField(name: "expires_after", value: String(expiry)) }
            if let team = xai?.teamId { multipart.appendField(name: "team_id", value: team) }
            multipart.appendFile(name: "file", filename: options.filename, contentType: options.mediaType, data: try convertInlineFileDataToData(options.data))
            let body = multipart.build()
            let requestHeaders = combineHeaders(headers, ["Content-Type": body.contentType]).compactMapValues { $0 }
            response = try await postToAPI(url: "\(config.baseURL)/files", headers: requestHeaders, body: PostBody(content: .data(body.data), values: nil), failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: fileResponseSchema), isAborted: options.abortSignal, fetch: config.fetch).value
        }
        let name = response.filename ?? options.filename
        return .init(providerReference: ["xai": response.id], mediaType: options.mediaType, filename: name?.isEmpty == false ? name : nil, byteSize: response.bytes, createdAt: response.createdAt.map(Date.init(timeIntervalSince1970:)), expiresAt: response.expiresAt.map(Date.init(timeIntervalSince1970:)), providerMetadata: response.metadata)
    }

    public func getFileMetadata(options: FilesV4GetFileMetadataCallOptions) async throws -> FilesV4GetFileMetadataResult {
        let id = try fileID(options.file)
        let response = try await getFromAPI(url: "\(config.baseURL)/files/\(xaiPathSegment(id))", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: fileResponseSchema), isAborted: options.abortSignal, fetch: config.fetch).value
        return .init(providerReference: ["xai": response.id], filename: response.filename, byteSize: response.bytes, createdAt: response.createdAt.map(Date.init(timeIntervalSince1970:)), expiresAt: response.expiresAt.map(Date.init(timeIntervalSince1970:)), providerMetadata: response.metadata)
    }

    public func downloadFile(options: FilesV4DownloadFileCallOptions) async throws -> FilesV4DownloadFileResult {
        let id = try fileID(options.file)
        let response = try await getFromAPI(url: "\(config.baseURL)/files/\(xaiPathSegment(id))/content", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createBinaryStreamResponseHandler(), isAborted: options.abortSignal, fetch: config.fetch)
        let mediaType = response.responseHeaders["content-type"]?.split(separator: ";", omittingEmptySubsequences: false).first?.trimmingCharacters(in: .whitespaces)
        return .init(content: response.value, mediaType: mediaType?.isEmpty == false ? mediaType : nil)
    }

    public func deleteFile(options: FilesV4DeleteFileCallOptions) async throws -> FilesV4DeleteFileResult {
        let id = try fileID(options.file)
        let response = try await deleteFromAPI(url: "\(config.baseURL)/files/\(xaiPathSegment(id))", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)), failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: deleteResponseSchema), isAborted: options.abortSignal, fetch: config.fetch).value
        return .init(providerReference: ["xai": response.id], deleted: response.deleted)
    }

    private func fileID(_ reference: SharedV4ProviderReference) throws -> String {
        guard let id = reference["xai"], !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InvalidArgumentError(argument: "file", message: "file reference is missing an 'xai' file id.") }
        return id
    }
}
