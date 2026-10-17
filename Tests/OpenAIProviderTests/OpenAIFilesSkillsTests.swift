import Foundation
import Testing
@testable import OpenAIProvider
import AISDKProvider
import AISDKProviderUtils

private actor OpenAIUploadRequestCapture {
    private var requests: [URLRequest] = []
    private var bodies: [Data] = []

    func append(_ request: URLRequest) {
        requests.append(request)
        if let body = request.httpBody {
            bodies.append(body)
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            bodies.append(body)
        }
    }

    func first() -> URLRequest? {
        requests.first
    }

    func firstBody() -> Data? {
        bodies.first
    }
}

private struct OpenAIMultipartPart {
    let headers: [String: String]
    let body: Data
}

private func openAIFetch(
    capture: OpenAIUploadRequestCapture,
    statusCode: Int = 200,
    responseBody: @escaping @Sendable (URLRequest) throws -> [String: Any]
) -> FetchFunction {
    { request in
        await capture.append(request)
        let body = try responseBody(request)
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return FetchResponse(body: .data(data), urlResponse: response)
    }
}

private func openAIExtractBoundary(from contentType: String) -> String? {
    guard let range = contentType.range(of: "boundary=") else { return nil }
    let tail = contentType[range.upperBound...]
    return tail.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "\t" }).first.map(String.init)
}

private func openAIParseMultipart(_ data: Data, boundary: String) -> [OpenAIMultipartPart] {
    let bytes = [UInt8](data)
    let boundaryBytes = Array("--\(boundary)".utf8)
    guard !boundaryBytes.isEmpty, bytes.count >= boundaryBytes.count else { return [] }

    var positions: [Int] = []
    var index = 0
    while index <= bytes.count - boundaryBytes.count {
        var matches = true
        for offset in 0..<boundaryBytes.count where bytes[index + offset] != boundaryBytes[offset] {
            matches = false
            break
        }
        if matches {
            positions.append(index)
            index += boundaryBytes.count
        } else {
            index += 1
        }
    }

    guard positions.count >= 2 else { return [] }

    var parts: [OpenAIMultipartPart] = []
    for positionIndex in 0..<(positions.count - 1) {
        let start = positions[positionIndex] + boundaryBytes.count
        let end = positions[positionIndex + 1]
        if start >= end { continue }

        var partStart = start
        if partStart + 1 < end, bytes[partStart] == 0x0D, bytes[partStart + 1] == 0x0A {
            partStart += 2
        }

        var partEnd = end
        if partEnd - 2 >= partStart, bytes[partEnd - 2] == 0x0D, bytes[partEnd - 1] == 0x0A {
            partEnd -= 2
        }
        if partStart >= partEnd { continue }

        let partData = Data(bytes[partStart..<partEnd])
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let separatorRange = partData.range(of: separator) else { continue }

        let headerData = partData.subdata(in: partData.startIndex..<separatorRange.lowerBound)
        let bodyData = partData.subdata(in: separatorRange.upperBound..<partData.endIndex)
        let headerString = String(data: headerData, encoding: .utf8) ?? ""

        var headers: [String: String] = [:]
        for rawLine in headerString.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        parts.append(OpenAIMultipartPart(headers: headers, body: bodyData))
    }
    return parts
}

private func openAIMultipartName(_ part: OpenAIMultipartPart) -> String? {
    openAIMultipartDispositionValue(part, key: "name")
}

private func openAIMultipartFilename(_ part: OpenAIMultipartPart) -> String? {
    openAIMultipartDispositionValue(part, key: "filename")
}

private func openAIMultipartDispositionValue(_ part: OpenAIMultipartPart, key: String) -> String? {
    guard let disposition = part.headers["content-disposition"] else { return nil }
    guard let range = disposition.range(of: "\(key)=\"") else { return nil }
    let tail = disposition[range.upperBound...]
    guard let endQuote = tail.firstIndex(of: "\"") else { return nil }
    return String(tail[..<endQuote])
}

private final class OpenAIFileLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private actor OpenAIFileChunks {
    private(set) var reads = 0

    func next() -> Data? {
        reads += 1
        return reads <= 2 ? Data([UInt8(reads)]) : nil
    }
}

@Suite("OpenAI Files and Skills")
struct OpenAIFilesSkillsTests {
    @Test("uploadFile sends OpenAI multipart payload and maps response metadata")
    func uploadFileSendsMultipartPayloadAndMapsMetadata() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider: any ProviderV4 = try createOpenAIProvider(settings: .init(
            baseURL: "https://api.openai.com/v1",
            apiKey: "test-api-key",
            organization: "test-org",
            project: "test-project",
            headers: ["Custom-Header": "custom-value"],
            fetch: openAIFetch(capture: capture) { _ in
                [
                    "id": "file-xyz789",
                    "object": "file",
                    "bytes": 1024,
                    "created_at": 1_700_000_000.5,
                    "filename": "test.csv",
                    "purpose": "assistants",
                    "status": "processed",
                    "expires_at": 1_700_003_600
                ]
            }
        ))

        let result = try await (try #require(try provider.files())).uploadFile(
            options: .init(
                data: .base64("AQID"),
                mediaType: "application/octet-stream",
                filename: "input.bin",
                headers: ["Custom-Header": "per-call"],
                providerOptions: [
                    "openai": [
                        "purpose": .string("assistants"),
                        "expiresAfter": .number(3600.5)
                    ]
                ]
            )
        )

        guard let request = await capture.first(),
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundary = openAIExtractBoundary(from: contentType),
              let body = request.httpBody else {
            Issue.record("Missing OpenAI file upload request")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/files")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "test-org")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == "test-project")
        #expect(request.value(forHTTPHeaderField: "Custom-Header") == "per-call")

        let parts = openAIParseMultipart(body, boundary: boundary)
        let filePart = parts.first { openAIMultipartName($0) == "file" }
        let purposePart = parts.first { openAIMultipartName($0) == "purpose" }
        let expiresAfterPart = parts.first { openAIMultipartName($0) == "expires_after[seconds]" }
        let anchorPart = parts.first { openAIMultipartName($0) == "expires_after[anchor]" }

        guard let filePart else {
            Issue.record("Missing OpenAI file multipart part")
            return
        }

        #expect(openAIMultipartFilename(filePart) == "input.bin")
        #expect(filePart.body == Data([1, 2, 3]))
        #expect(String(data: purposePart?.body ?? Data(), encoding: .utf8) == "assistants")
        #expect(String(data: expiresAfterPart?.body ?? Data(), encoding: .utf8) == "3600.5")
        #expect(String(data: anchorPart?.body ?? Data(), encoding: .utf8) == "created_at")

        #expect(result.providerReference["openai"] == "file-xyz789")
        #expect(result.filename == "test.csv")
        #expect(result.mediaType == "application/octet-stream")
        #expect(result.providerMetadata?["openai"]?["filename"] == .string("test.csv"))
        #expect(result.providerMetadata?["openai"]?["purpose"] == .string("assistants"))
        #expect(result.providerMetadata?["openai"]?["bytes"] == .number(1024))
        #expect(result.byteSize == 1024)
        #expect(result.createdAt == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(result.expiresAt == Date(timeIntervalSince1970: 1_700_003_600))
        #expect(result.providerMetadata?["openai"]?["createdAt"] == .number(1_700_000_000.5))
        #expect(result.providerMetadata?["openai"]?["status"] == .string("processed"))
        #expect(result.providerMetadata?["openai"]?["expiresAt"] == .number(1_700_003_600))
    }

    @Test("uploadFile defaults purpose to assistants")
    func uploadFileDefaultsPurpose() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider: any ProviderV4 = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIFetch(capture: capture) { _ in
                ["id": "file-abc123"]
            }
        ))

        _ = try await (try #require(try provider.files())).uploadFile(
            options: .init(
                data: .data(Data([1, 2, 3])),
                mediaType: "application/octet-stream"
            )
        )

        guard let request = await capture.first(),
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundary = openAIExtractBoundary(from: contentType),
              let body = request.httpBody else {
            Issue.record("Missing OpenAI file upload request")
            return
        }

        let parts = openAIParseMultipart(body, boundary: boundary)
        let filePart = parts.first { openAIMultipartName($0) == "file" }
        let purposePart = parts.first { openAIMultipartName($0) == "purpose" }
        guard let filePart else {
            Issue.record("Missing OpenAI file multipart part")
            return
        }
        #expect(openAIMultipartFilename(filePart) == "blob")
        #expect(String(data: purposePart?.body ?? Data(), encoding: .utf8) == "assistants")
    }

    @Test("stream uploads send expiry fields before the binary file")
    func uploadFileStreamsMultipart() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            headers: ["X-Upload": "configured"],
            fetch: openAIFetch(capture: capture) { _ in ["id": "file-stream", "bytes": 4] }
        ))
        let source = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0x00, 0xFF]))
            continuation.yield(Data([0x0D, 0x0A]))
            continuation.finish()
        }
        let files = try #require(try provider.files())
        let result = try await files.uploadFile(options: .init(
            data: .stream(source),
            mediaType: "application/octet-stream",
            headers: ["X-Upload": "per-call"],
            providerOptions: ["openai": ["purpose": "batch", "expiresAfter": 60]]
        ))

        let request = try #require(await capture.first())
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(openAIExtractBoundary(from: contentType))
        let body = try #require(await capture.firstBody())
        let parts = openAIParseMultipart(body, boundary: boundary)
        try #require(parts.count == 4)
        #expect(parts.compactMap(openAIMultipartName) == ["purpose", "expires_after[anchor]", "expires_after[seconds]", "file"])
        #expect(String(decoding: parts[0].body, as: UTF8.self) == "batch")
        #expect(String(decoding: parts[1].body, as: UTF8.self) == "created_at")
        #expect(String(decoding: parts[2].body, as: UTF8.self) == "60")
        #expect(parts[3].body == Data([0x00, 0xFF, 0x0D, 0x0A]))
        #expect(openAIMultipartFilename(parts[3]) == "blob")
        #expect(request.value(forHTTPHeaderField: "X-Upload") == "per-call")
        #expect(result.providerReference == ["openai": "file-stream"])
        #expect(result.byteSize == 4)
    }

    @Test("upload validation releases stream data before rejecting provider options", arguments: [
        ["purpose": JSONValue.null],
        ["expiresAfter": JSONValue.string("invalid")],
        ["expiresAfter": JSONValue.number(.infinity)]
    ])
    func uploadFileRejectsOptions(_ options: JSONObject) async throws {
        let lifetime = OpenAIFileLifetime()
        let (source, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        continuation.onTermination = { reason in
            if case .cancelled = reason { lifetime.cancel() }
        }
        defer { continuation.finish() }
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: { _ in throw URLError(.cannotConnectToHost) }
        ))
        let files = try #require(try provider.files())
        let error = await #expect(throws: InvalidArgumentError.self) {
            _ = try await files.uploadFile(options: .init(
                data: .stream(source), mediaType: "text/plain", providerOptions: ["openai": options]
            ))
        }
        #expect(error?.argument == "providerOptions")
        #expect(lifetime.isCancelled)
    }

    @Test("a lazy header failure releases stream upload data")
    func uploadHeaderFailureReleasesSource() async {
        let lifetime = OpenAIFileLifetime()
        let (source, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        continuation.onTermination = { reason in
            if case .cancelled = reason { lifetime.cancel() }
        }
        defer { continuation.finish() }
        let files = OpenAIFiles(config: .init(
            provider: "openai.files", baseURL: "https://api.openai.com/v1",
            headers: { throw URLError(.userAuthenticationRequired) }, fetch: nil
        ))
        let error = await #expect(throws: URLError.self) {
            _ = try await files.uploadFile(options: .init(data: .stream(source), mediaType: "text/plain"))
        }
        #expect(error?.code == .userAuthenticationRequired)
        #expect(lifetime.isCancelled)
    }

    @Test("an aborted stream upload releases its producer")
    func uploadAbortReleasesSource() async throws {
        let lifetime = OpenAIFileLifetime()
        let (source, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        continuation.onTermination = { reason in
            if case .cancelled = reason { lifetime.cancel() }
        }
        defer { continuation.finish() }
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key", fetch: { _ in throw URLError(.cannotConnectToHost) }
        ))
        let files = try #require(try provider.files())
        await #expect(throws: CancellationError.self) {
            _ = try await files.uploadFile(options: .init(
                data: .stream(source), mediaType: "text/plain", abortSignal: { true }
            ))
        }
        #expect(lifetime.isCancelled)
    }

    @Test("expiry uses the finite JavaScript numeric form", arguments: [
        (1e20, "100000000000000000000"), (1e-7, "1e-7"), (-0.0, "0"),
        (1e-6, "0.000001"), (1e21, "1e+21"), (9_223_372_036_854_775_808.0, "9223372036854776000")
    ])
    func uploadExpiryFormatting(_ value: Double, _ expected: String) async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key", fetch: openAIFetch(capture: capture) { _ in ["id": "file-1"] }
        ))
        let files = try #require(try provider.files())
        _ = try await files.uploadFile(options: .init(
            data: .text("x"), mediaType: "text/plain", providerOptions: ["openai": ["expiresAfter": .number(value)]]
        ))
        let request = try #require(await capture.first())
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(openAIExtractBoundary(from: contentType))
        let parts = openAIParseMultipart(try #require(request.httpBody), boundary: boundary)
        let expiry = try #require(parts.first { openAIMultipartName($0) == "expires_after[seconds]" })
        #expect(String(decoding: expiry.body, as: UTF8.self) == expected)
    }

    @Test("upload omits an empty response filename instead of falling back")
    func uploadEmptyFilename() async throws {
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key", fetch: openAIFetch(capture: OpenAIUploadRequestCapture()) { _ in ["id": "file-1", "filename": ""] }
        ))
        let files = try #require(try provider.files())
        let result = try await files.uploadFile(options: .init(data: .text("x"), mediaType: "text/plain", filename: "input.txt"))
        #expect(result.filename == nil)
        #expect(result.providerMetadata?["openai"]?["filename"] == .string(""))
    }

    @Test("metadata reads preserve file IDs as one URL segment", arguments: [
        (".", "%252E"), ("..", "%252E%252E"), ("file/a?b#c% d", "file%2Fa%3Fb%23c%25%20d")
    ])
    func getFileMetadata(_ fileId: String, _ encoded: String) async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            baseURL: "https://files.example.test/v1", apiKey: "test-api-key",
            headers: ["X-File": "configured"],
            fetch: openAIFetch(capture: capture) { _ in
                ["id": fileId, "filename": "", "bytes": 0, "created_at": 1.5, "expires_at": NSNull()]
            }
        ))
        let files = try #require(try provider.files())
        let reader = try #require(files as? any FilesV4MetadataReader)
        let result = try await reader.getFileMetadata(options: .init(
            file: ["openai": fileId, "other": "ignored"], headers: ["X-File": "per-call"]
        ))
        let request = try #require(await capture.first())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://files.example.test/v1/files/\(encoded)")
        #expect(request.value(forHTTPHeaderField: "X-File") == "per-call")
        #expect(result.providerReference == ["openai": fileId])
        #expect(result.filename == "")
        #expect(result.byteSize == 0)
        #expect(result.createdAt == Date(timeIntervalSince1970: 1.5))
        #expect(result.expiresAt == nil)
        #expect(result.providerMetadata?["openai"]?["createdAt"] == .number(1.5))
    }

    @Test("metadata rejects missing or blank OpenAI references", arguments: [
        ["other": "file-1"], ["openai": " \t\n"]
    ])
    func rejectsFileReference(_ reference: SharedV4ProviderReference) async throws {
        let provider = try createOpenAIProvider(settings: .init(apiKey: "test-api-key"))
        let files = try #require(try provider.files())
        let reader = try #require(files as? any FilesV4MetadataReader)
        let error = await #expect(throws: InvalidArgumentError.self) {
            _ = try await reader.getFileMetadata(options: .init(file: reference))
        }
        #expect(error?.argument == "file")
        #expect(error?.message == "file reference is missing an 'openai' file id.")
    }

    @Test("file download remains pull-based and strips media type parameters")
    func downloadPullsBytes() async throws {
        let chunks = OpenAIFileChunks()
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: { request in
                await capture.append(request)
                return FetchResponse(
                    body: .stream(AsyncThrowingStream { await chunks.next() }),
                    urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/jsonl; charset=utf-8"])!
                )
            }
        ))
        let files = try #require(try provider.files())
        let downloader = try #require(files as? any FilesV4Downloader)
        let result = try await downloader.downloadFile(options: .init(file: ["openai": "file/1"], headers: ["X-File": "download"]))
        #expect(await chunks.reads == 0)
        let request = try #require(await capture.first())
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/files/file%2F1/content")
        #expect(request.value(forHTTPHeaderField: "X-File") == "download")
        #expect(result.mediaType == "application/jsonl")
        var iterator = result.content.makeAsyncIterator()
        #expect(try await iterator.next() == Data([1]))
        #expect(await chunks.reads == 1)
        #expect(try await iterator.next() == Data([2]))
        #expect(try await iterator.next() == nil)
    }

    @Test("delete uses the provider result rather than assuming success")
    func deleteFile() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key", fetch: openAIFetch(capture: capture) { _ in ["id": "file-1", "deleted": false] }
        ))
        let files = try #require(try provider.files())
        let deleter = try #require(files as? any FilesV4Deleter)
        let result = try await deleter.deleteFile(options: .init(file: ["openai": "file-1"], headers: ["X-File": "delete"]))
        let request = try #require(await capture.first())
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/files/file-1")
        #expect(request.value(forHTTPHeaderField: "X-File") == "delete")
        #expect(result.providerReference == ["openai": "file-1"])
        #expect(result.deleted == false)
    }

    @Test("invalid delete responses retain API response diagnostics")
    func deleteValidatesResponse() async throws {
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key", fetch: openAIFetch(capture: OpenAIUploadRequestCapture()) { _ in ["id": "file-1", "deleted": "yes"] }
        ))
        let files = try #require(try provider.files())
        let deleter = try #require(files as? any FilesV4Deleter)
        let error = await #expect(throws: APICallError.self) {
            _ = try await deleter.deleteFile(options: .init(file: ["openai": "file-1"]))
        }
        #expect(error?.statusCode == 200)
        #expect(error?.message == "Invalid JSON response")
        #expect(error?.responseBody?.contains("deleted") == true)
    }

    @Test("file metadata exposes OpenAI HTTP errors")
    func metadataHTTPError() async throws {
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key", fetch: openAIFetch(capture: OpenAIUploadRequestCapture(), statusCode: 403) { _ in
                ["error": ["message": "File access denied", "type": "invalid_request_error"]]
            }
        ))
        let files = try #require(try provider.files())
        let reader = try #require(files as? any FilesV4MetadataReader)
        let error = await #expect(throws: APICallError.self) {
            _ = try await reader.getFileMetadata(options: .init(file: ["openai": "file-1"]))
        }
        #expect(error?.statusCode == 403)
        #expect(error?.message == "File access denied")
        #expect(error?.isRetryable == false)
    }

    @Test("uploadSkill sends OpenAI skill files and maps warnings/result")
    func uploadSkillSendsMultipartPayloadAndMapsResult() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider: any ProviderV4 = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIFetch(capture: capture) { _ in
                [
                    "id": "skill_699fc58f408c8191825d8d06ae75fd5c06de7b381a5db7f5",
                    "name": "test-capture-skill",
                    "description": "A test skill for fixture capture",
                    "default_version": "1",
                    "latest_version": "1",
                    "created_at": 1_772_078_479.25,
                    "updated_at": 1_772_078_480.75
                ]
            }
        ))

        let result = try await (try #require(try provider.skills())).uploadSkill(
            options: .init(
                files: [
                    SkillsV4File(path: "index.ts", data: .text("console.log(\"hello\")"))
                ],
                displayTitle: "My Skill"
            )
        )

        guard let request = await capture.first(),
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundary = openAIExtractBoundary(from: contentType),
              let body = request.httpBody else {
            Issue.record("Missing OpenAI skill upload request")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/skills")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")

        let parts = openAIParseMultipart(body, boundary: boundary)
        let filePart = parts.first { openAIMultipartName($0) == "files[]" }
        guard let filePart else {
            Issue.record("Missing OpenAI skill file multipart part")
            return
        }

        #expect(openAIMultipartFilename(filePart) == "index.ts")
        #expect(String(data: filePart.body, encoding: .utf8) == "console.log(\"hello\")")

        #expect(result.providerReference["openai"] == "skill_699fc58f408c8191825d8d06ae75fd5c06de7b381a5db7f5")
        #expect(result.name == "test-capture-skill")
        #expect(result.description == "A test skill for fixture capture")
        #expect(result.latestVersion == "1")
        #expect(result.providerMetadata?["openai"]?["defaultVersion"] == .string("1"))
        #expect(result.providerMetadata?["openai"]?["createdAt"] == .number(1_772_078_479.25))
        #expect(result.providerMetadata?["openai"]?["updatedAt"] == .number(1_772_078_480.75))
        #expect(result.warnings == [.unsupported(feature: "displayTitle", details: nil)])
    }

    @Test("uploadSkill sends binary OpenAI skill file without displayTitle warning")
    func uploadSkillSendsBinaryFileWithoutDisplayTitleWarning() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider: any ProviderV4 = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIFetch(capture: capture) { _ in
                [
                    "id": "skill_binary",
                    "name": "binary-skill",
                    "created_at": 1_772_078_500
                ]
            }
        ))

        let result = try await (try #require(try provider.skills())).uploadSkill(
            options: .init(
                files: [
                    SkillsV4File(path: "data.bin", data: .data(Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])))
                ]
            )
        )

        guard let request = await capture.first(),
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundary = openAIExtractBoundary(from: contentType),
              let body = request.httpBody else {
            Issue.record("Missing OpenAI skill upload request")
            return
        }

        let parts = openAIParseMultipart(body, boundary: boundary)
        let filePart = parts.first { openAIMultipartName($0) == "files[]" }
        guard let filePart else {
            Issue.record("Missing OpenAI skill file multipart part")
            return
        }

        #expect(openAIMultipartFilename(filePart) == "data.bin")
        #expect(filePart.body == Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]))
        #expect(result.providerReference["openai"] == "skill_binary")
        #expect(result.name == "binary-skill")
        #expect(result.warnings == [])
    }
}
