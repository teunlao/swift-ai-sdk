import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct DeepSeekFilesOptions: Codable, Sendable, Equatable {
    public var expiresAfter: Int?
    public init(expiresAfter: Int? = nil) { self.expiresAfter = expiresAfter }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expiresAfter = try c.decodeIfPresent(Int.self, forKey: .expiresAfter)
        if let expiresAfter, !(3600...2592000).contains(expiresAfter) {
            throw DecodingError.dataCorruptedError(forKey: .expiresAfter, in: c, debugDescription: "expiresAfter must be between 3600 and 2592000 seconds")
        }
    }
}

private struct DeepSeekUploadResponse: Decodable, Sendable {
    let id: String
    let object: String?
    let bytes: Int?
    let createdAt: Int?
    let filename: String?
    let purpose: String?
    let expiresAt: Int?
    enum CodingKeys: String, CodingKey {
        case id, object, bytes, filename, purpose
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        object = try c.decodeIfPresent(String.self, forKey: .object)
        bytes = try c.decodeIfPresent(Int.self, forKey: .bytes)
        createdAt = try c.decodeIfPresent(Int.self, forKey: .createdAt)
        filename = try c.decodeIfPresent(String.self, forKey: .filename)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose)
        expiresAt = try c.decodeIfPresent(Int.self, forKey: .expiresAt)
        if let object, object != "file" { throw DecodingError.dataCorruptedError(forKey: .object, in: c, debugDescription: "Expected file object") }
        if let purpose, purpose != "user_data" { throw DecodingError.dataCorruptedError(forKey: .purpose, in: c, debugDescription: "Expected user_data purpose") }
        for (key, value) in [(CodingKeys.bytes, bytes), (.createdAt, createdAt), (.expiresAt, expiresAt)] {
            if let value, value < 0 { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected nonnegative integer") }
        }
    }
}

public final class DeepSeekFiles: FilesV4 {
    public let specificationVersion = "v4"
    public let provider = "deepseek.files"
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String]
    private let fetch: FetchFunction?
    init(baseURL: String, headers: @escaping @Sendable () throws -> [String: String], fetch: FetchFunction?) {
        self.baseURL = baseURL; self.headers = headers; self.fetch = fetch
    }
    public func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        let settings = try await parseProviderOptions(provider: "deepseek", providerOptions: options.providerOptions,
                                                     schema: FlexibleSchema(Schema<DeepSeekFilesOptions>.codable(DeepSeekFilesOptions.self, jsonSchema: ["type": "object"])))
        let bytes = try convertInlineFileDataToData(options.data)
        guard bytes.count <= 64 * 1024 * 1024 else {
            throw InvalidArgumentError(argument: "data", message: "DeepSeek file uploads must not exceed 64 MiB (67,108,864 bytes). Received \(bytes.count) bytes.")
        }
        if let filename = options.filename, filename.unicodeScalars.count > 512 {
            throw InvalidArgumentError(argument: "filename", message: "DeepSeek filenames must not exceed 512 characters. Received \(filename.unicodeScalars.count) characters.")
        }
        let supported = ["image/gif", "image/jpeg", "image/jpg", "image/png", "image/webp"]
        let normalized = options.mediaType.split(separator: ";", omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let detected = detectMediaType(data: bytes)
        if let detected, !supported.contains(detected) {
            throw InvalidArgumentError(argument: "data", message: "DeepSeek file uploads support JPEG, PNG, GIF, and WebP images. Detected unsupported file content type \"\(detected)\".")
        }
        if !supported.contains(normalized) {
            let generic = ["", "application/binary", "application/octet-stream", "binary/octet-stream", "image", "image/*"]
            guard generic.contains(normalized) else {
                throw InvalidArgumentError(argument: "mediaType", message: "DeepSeek file uploads support JPEG, PNG, GIF, and WebP images. Received unsupported media type \"\(options.mediaType)\".")
            }
            let extensionName = options.filename.flatMap { name -> String? in
                guard let dot = name.lastIndex(of: ".") else { return nil }
                return String(name[name.index(after: dot)...]).lowercased()
            }
            guard detected != nil || extensionName.map({ ["gif", "jpeg", "jpg", "png", "webp"].contains($0) }) == true else {
                throw InvalidArgumentError(argument: "mediaType", message: "DeepSeek file uploads support JPEG, PNG, GIF, and WebP images. Provide a supported media type or a filename ending in .jpg, .jpeg, .png, .gif, or .webp. Received \"\(options.mediaType)\".")
            }
        }
        var builder = MultipartFormDataBuilder()
        builder.appendFile(name: "file", filename: options.filename ?? "blob", contentType: options.mediaType, data: bytes)
        builder.appendField(name: "purpose", value: "user_data")
        if let seconds = settings?.expiresAfter {
            builder.appendField(name: "expires_after[anchor]", value: "created_at")
            builder.appendField(name: "expires_after[seconds]", value: String(seconds))
        }
        let form = builder.build()
        var requestHeaders = combineHeaders(try headers().mapValues(Optional.some), options.headers?.mapValues(Optional.some))
        requestHeaders["Content-Type"] = form.contentType
        let result = try await postToAPI(url: baseURL + "/files", headers: requestHeaders.compactMapValues { $0 },
                                         body: .init(content: .data(form.data), values: nil),
                                         failedResponseHandler: deepSeekFailedResponseHandler,
                                         successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema<DeepSeekUploadResponse>.codable(DeepSeekUploadResponse.self, jsonSchema: ["type": "object"]))),
                                         isAborted: options.abortSignal, fetch: fetch).value
        var metadata: [String: JSONValue] = [:]
        if let value = result.object { metadata["object"] = .string(value) }
        if let value = result.filename { metadata["filename"] = .string(value) }
        if let value = result.purpose { metadata["purpose"] = .string(value) }
        if let value = result.bytes { metadata["bytes"] = .number(Double(value)) }
        if let value = result.createdAt { metadata["createdAt"] = .number(Double(value)) }
        if let value = result.expiresAt { metadata["expiresAt"] = .number(Double(value)) }
        let filename = result.filename ?? options.filename
        return .init(providerReference: ["deepseek": result.id], mediaType: options.mediaType,
                     filename: filename?.isEmpty == false ? filename : nil,
                     providerMetadata: ["deepseek": metadata], warnings: [])
    }
}
