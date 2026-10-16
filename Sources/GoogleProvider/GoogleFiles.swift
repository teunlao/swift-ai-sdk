import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleFilesUploadOptions: Sendable, Codable, Equatable {
    public var displayName: String?
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public init(displayName: String? = nil, pollIntervalMs: Double? = nil, pollTimeoutMs: Double? = nil) {
        self.displayName = displayName; self.pollIntervalMs = pollIntervalMs; self.pollTimeoutMs = pollTimeoutMs
    }
}
private let googleFilesOptionsSchema = FlexibleSchema(Schema<GoogleFilesUploadOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let options = try JSONDecoder().decode(GoogleFilesUploadOptions.self, from: JSONEncoder().encode(jsonValue(from: value)))
        if let interval = options.pollIntervalMs, interval <= 0 { throw InvalidArgumentError(argument: "pollIntervalMs", message: "pollIntervalMs must be positive") }
        if let timeout = options.pollTimeoutMs, timeout <= 0 { throw InvalidArgumentError(argument: "pollTimeoutMs", message: "pollTimeoutMs must be positive") }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))
private struct GoogleFileResource: Codable, Sendable {
    let name: String
    let displayName: String?
    let mimeType: String
    let sizeBytes: String?
    let createTime: String?
    let updateTime: String?
    let expirationTime: String?
    let sha256Hash: String?
    let uri: String
    let state: String
}
private let googleFileResponseSchema = FlexibleSchema(Schema<GoogleFileResource>.codable(GoogleFileResource.self, jsonSchema: .object(["type": .string("object")])))

public final class GoogleFiles: FilesV4 {
    public struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        public init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?], fetch: FetchFunction? = nil) {
            self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch
        }
    }
    private let config: Config
    public var provider: String { config.provider }
    public let specificationVersion = "v4"
    public init(config: Config) { self.config = config }

    public func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        let google = try await parseProviderOptions(provider: "google", providerOptions: options.providerOptions, schema: googleFilesOptionsSchema)
        let bytes = try convertInlineFileDataToData(options.data)
        let resolved = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let headers = combineHeaders(resolved.mapValues { Optional($0) }, [
            "X-Goog-Upload-Protocol": "resumable",
            "X-Goog-Upload-Command": "start",
            "X-Goog-Upload-Header-Content-Length": String(bytes.count),
            "X-Goog-Upload-Header-Content-Type": options.mediaType,
            "Content-Type": "application/json"
        ]).compactMapValues { $0 }
        var fileInfo: [String: JSONValue] = [:]
        if let name = google?.displayName { fileInfo["display_name"] = .string(name) }
        let origin = config.baseURL.hasSuffix("/v1beta") ? String(config.baseURL.dropLast(7)) : config.baseURL
        let initial = try await request(url: "\(origin)/upload/v1beta/files", headers: headers, body: JSONEncoder().encode(JSONValue.object(["file": .object(fileInfo)])), abortSignal: options.abortSignal)
        guard (200...299).contains(initial.response.statusCode) else {
            throw GoogleFilesError(name: "GOOGLE_FILES_UPLOAD_ERROR", message: "Failed to initiate resumable upload: \(initial.response.statusCode) \(String(decoding: initial.body, as: UTF8.self))")
        }
        guard let uploadURL = initial.response.value(forHTTPHeaderField: "x-goog-upload-url"), !uploadURL.isEmpty else { throw GoogleFilesError(name: "GOOGLE_FILES_UPLOAD_ERROR", message: "No upload URL returned from initiation request") }
        let uploaded = try await request(url: uploadURL, headers: ["X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize"], body: bytes, abortSignal: options.abortSignal)
        guard (200...299).contains(uploaded.response.statusCode) else { throw GoogleFilesError(name: "GOOGLE_FILES_UPLOAD_ERROR", message: "Failed to upload file data: \(uploaded.response.statusCode) \(String(decoding: uploaded.body, as: UTF8.self))") }
        struct Uploaded: Decodable { let file: GoogleFileResource }
        var file = try JSONDecoder().decode(Uploaded.self, from: uploaded.body).file
        let interval = google?.pollIntervalMs ?? 2000
        let timeout = google?.pollTimeoutMs ?? 300000
        let start = Date()
        while file.state == "PROCESSING" {
            if Date().timeIntervalSince(start) * 1000 > timeout { throw GoogleFilesError(name: "GOOGLE_FILES_UPLOAD_TIMEOUT", message: "File processing timed out after \(timeout.formatted(.number.grouping(.never)))ms") }
            try await delay(Int(interval), abortSignal: options.abortSignal)
            let components = file.name.components(separatedBy: "/")
            let path = components.count == 2 && components[0] == "files" && !components[1].isEmpty ? "files/" + encodeGoogleFileSegment(components[1]) : encodeGoogleFileSegment(file.name)
            file = try await getFromAPI(url: "\(config.baseURL)/\(path)", headers: resolved, failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleFileResponseSchema), isAborted: options.abortSignal, fetch: config.fetch).value
        }
        if file.state == "FAILED" { throw GoogleFilesError(name: "GOOGLE_FILES_UPLOAD_FAILED", message: "File processing failed for \(file.name)") }
        var metadata: [String: JSONValue] = ["name": .string(file.name), "mimeType": .string(file.mimeType), "state": .string(file.state), "uri": .string(file.uri)]
        if let value = file.displayName { metadata["displayName"] = .string(value) }
        if let value = file.sizeBytes { metadata["sizeBytes"] = .string(value) }
        if let value = file.createTime { metadata["createTime"] = .string(value) }
        if let value = file.updateTime { metadata["updateTime"] = .string(value) }
        if let value = file.expirationTime { metadata["expirationTime"] = .string(value) }
        if let value = file.sha256Hash { metadata["sha256Hash"] = .string(value) }
        return .init(providerReference: ["google": file.uri], mediaType: file.mimeType, providerMetadata: ["google": metadata], warnings: options.filename != nil ? [.unsupported(feature: "filename", details: nil)] : [])
    }

    private func request(url: String, headers: [String: String], body: Data, abortSignal: (@Sendable () -> Bool)?) async throws -> (response: HTTPURLResponse, body: Data) {
        guard let url = URL(string: url) else { throw InvalidArgumentError(argument: "url", message: "Invalid upload URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let fetch = config.fetch ?? defaultFetchFunction()
        let outbound = request
        if abortSignal?() == true { throw CancellationError() }
        let operation: @Sendable () async throws -> (response: HTTPURLResponse, body: Data) = {
            let response = try await fetch(outbound)
            guard let http = response.urlResponse as? HTTPURLResponse else { throw GoogleFilesError(name: "GOOGLE_FILES_UPLOAD_ERROR", message: "Invalid upload response") }
            return (http, try await response.body.collectData())
        }
        guard let abortSignal else { return try await operation() }
        return try await withThrowingTaskGroup(of: (response: HTTPURLResponse, body: Data).self) { group in
            group.addTask { try await operation() }
            group.addTask {
                while !Task.isCancelled {
                    if abortSignal() { throw CancellationError() }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

private func encodeGoogleFileSegment(_ value: String) -> String {
    if value == "." { return "%252E" }
    if value == ".." { return "%252E%252E" }
    return value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")) ?? value
}
private struct GoogleFilesError: AISDKError, Sendable {
    static let errorDomain = "google.files.error"
    let name: String
    let message: String
    let cause: (any Error)? = nil
}
