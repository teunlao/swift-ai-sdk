import Foundation
import Testing
@testable import OpenAIProvider
import AISDKProvider
import AISDKProviderUtils

private actor OpenAIUploadRequestCapture {
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }

    func first() -> URLRequest? {
        requests.first
    }
}

private struct OpenAIMultipartPart {
    let headers: [String: String]
    let body: Data
}

private func openAIFetch(
    capture: OpenAIUploadRequestCapture,
    responseBody: @escaping @Sendable (URLRequest) throws -> [String: Any]
) -> FetchFunction {
    { request in
        await capture.append(request)
        let body = try responseBody(request)
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
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

@Suite("OpenAI Files and Skills")
struct OpenAIFilesSkillsTests {
    @Test("provider wires files and skills interfaces with upstream ids")
    func providerWiresUploadInterfaces() throws {
        let provider = try createOpenAIProvider(settings: .init(apiKey: "test-api-key"))

        #expect(provider.files().provider == "openai.files")
        #expect(provider.files().specificationVersion == "v4")
        #expect(provider.skills().provider == "openai.skills")
        #expect(provider.skills().specificationVersion == "v4")
    }

    @Test("uploadFile sends OpenAI multipart payload and maps response metadata")
    func uploadFileSendsMultipartPayloadAndMapsMetadata() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
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
                    "created_at": 1_700_000_000,
                    "filename": "test.csv",
                    "purpose": "assistants",
                    "status": "processed",
                    "expires_at": 1_700_003_600
                ]
            }
        ))

        let result = try await provider.files().uploadFile(
            options: .init(
                data: .base64("AQID"),
                mediaType: "application/octet-stream",
                filename: "input.bin",
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
        #expect(request.value(forHTTPHeaderField: "Custom-Header") == "custom-value")

        let parts = openAIParseMultipart(body, boundary: boundary)
        let filePart = parts.first { openAIMultipartName($0) == "file" }
        let purposePart = parts.first { openAIMultipartName($0) == "purpose" }
        let expiresAfterPart = parts.first { openAIMultipartName($0) == "expires_after" }

        guard let filePart else {
            Issue.record("Missing OpenAI file multipart part")
            return
        }

        #expect(openAIMultipartFilename(filePart) == "input.bin")
        #expect(filePart.body == Data([1, 2, 3]))
        #expect(String(data: purposePart?.body ?? Data(), encoding: .utf8) == "assistants")
        #expect(String(data: expiresAfterPart?.body ?? Data(), encoding: .utf8) == "3600.5")

        #expect(result.providerReference["openai"] == "file-xyz789")
        #expect(result.filename == "test.csv")
        #expect(result.mediaType == "application/octet-stream")
        #expect(result.providerMetadata?["openai"]?["filename"] == .string("test.csv"))
        #expect(result.providerMetadata?["openai"]?["purpose"] == .string("assistants"))
        #expect(result.providerMetadata?["openai"]?["bytes"] == .number(1024))
        #expect(result.providerMetadata?["openai"]?["createdAt"] == .number(1_700_000_000))
        #expect(result.providerMetadata?["openai"]?["status"] == .string("processed"))
        #expect(result.providerMetadata?["openai"]?["expiresAt"] == .number(1_700_003_600))
    }

    @Test("uploadFile defaults purpose to assistants")
    func uploadFileDefaultsPurpose() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIFetch(capture: capture) { _ in
                ["id": "file-abc123"]
            }
        ))

        _ = try await provider.files().uploadFile(
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
        #expect(openAIMultipartFilename(filePart) == nil)
        #expect(String(data: purposePart?.body ?? Data(), encoding: .utf8) == "assistants")
    }

    @Test("uploadSkill sends OpenAI skill files and maps warnings/result")
    func uploadSkillSendsMultipartPayloadAndMapsResult() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIFetch(capture: capture) { _ in
                [
                    "id": "skill_699fc58f408c8191825d8d06ae75fd5c06de7b381a5db7f5",
                    "name": "test-capture-skill",
                    "description": "A test skill for fixture capture",
                    "default_version": "1",
                    "latest_version": "1",
                    "created_at": 1_772_078_479
                ]
            }
        ))

        let result = try await provider.skills().uploadSkill(
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
        #expect(result.providerMetadata?["openai"]?["createdAt"] == .number(1_772_078_479))
        #expect(result.warnings == [.unsupported(feature: "displayTitle", details: nil)])
    }

    @Test("uploadSkill sends binary OpenAI skill file without displayTitle warning")
    func uploadSkillSendsBinaryFileWithoutDisplayTitleWarning() async throws {
        let capture = OpenAIUploadRequestCapture()
        let provider = try createOpenAIProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: openAIFetch(capture: capture) { _ in
                [
                    "id": "skill_binary",
                    "name": "binary-skill",
                    "created_at": 1_772_078_500
                ]
            }
        ))

        let result = try await provider.skills().uploadSkill(
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
