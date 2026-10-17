import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

@Suite("AnthropicFiles")
struct AnthropicFilesTests {
    private func makeFetch(capture: URLRequestCapture) -> FetchFunction {
        { request in
            await capture.append(request)

            let body: [String: Any] = [
                "id": "file-abc123",
                "type": "file",
                "filename": "test.pdf",
                "mime_type": "application/pdf",
                "size_bytes": 12_345,
                "created_at": "2025-04-14T12:00:00Z",
                "downloadable": true
            ]

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

    @Test("uploadFile sends multipart payload with anthropic files beta header")
    func uploadFileSendsMultipartPayload() async throws {
        let capture = URLRequestCapture()
        let provider: any ProviderV4 = createAnthropic(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let result = try await #require(try provider.files()).uploadFile(
            options: .init(
                data: .data(Data([0x25, 0x50, 0x44, 0x46])),
                mediaType: "application/pdf",
                filename: "custom-name.pdf"
            )
        )

        guard let request = await capture.first() else {
            Issue.record("Expected request capture")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/files")
        #expect(headers["anthropic-beta"] == "files-api-2025-04-14")
        #expect(headers["x-api-key"] == "test-api-key")

        guard let contentType = headers["Content-Type"] ?? headers["content-type"],
              let boundary = extractBoundary(from: contentType),
              let body = request.httpBody else {
            Issue.record("Missing multipart body")
            return
        }

        let parts = parseMultipart(body, boundary: boundary)
        let filePart = parts.first { multipartName($0) == "file" }
        let bodyText = String(data: body, encoding: .utf8)

        #expect(filePart != nil)
        #expect(multipartFilename(filePart!) == "custom-name.pdf")
        #expect(bodyText?.contains("Content-Type: application/pdf") == true)
        #expect(result.providerReference["anthropic"] == "file-abc123")
    }

    @Test("uploadFile call headers override defaults and preserve other provider headers")
    func uploadFileHeaderOverrides() async throws {
        let capture = URLRequestCapture()
        let provider: any ProviderV4 = createAnthropic(settings: .init(
            apiKey: "provider-key",
            headers: ["x-upload-scope": "provider", "x-provider-only": "retained", "Content-Type": "application/custom-file"],
            fetch: makeFetch(capture: capture)
        ))

        _ = try await #require(try provider.files()).uploadFile(options: .init(
            data: .text("file"),
            mediaType: "text/plain",
            headers: [
                "x-upload-scope": "request", "x-upload-extra": "forwarded",
                "x-api-key": "request-key", "anthropic-beta": "custom-upload-beta",
            ]
        ))

        let request = try #require(await capture.first())
        #expect(request.value(forHTTPHeaderField: "x-upload-scope") == "request")
        #expect(request.value(forHTTPHeaderField: "x-provider-only") == "retained")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/custom-file")
        #expect(request.value(forHTTPHeaderField: "x-upload-extra") == "forwarded")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "request-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "custom-upload-beta")
    }

    @Test("uploadFile preserves cancellation from an already aborted signal")
    func uploadFileCancellation() async throws {
        let provider: any ProviderV4 = createAnthropic(settings: .init(
            apiKey: "test-key",
            fetch: makeFetch(capture: URLRequestCapture())
        ))

        await #expect(throws: CancellationError.self) {
            _ = try await #require(try provider.files()).uploadFile(options: .init(
                data: .text("file"), mediaType: "text/plain", abortSignal: { true }
            ))
        }
    }

    @Test("uploadFile rejects malformed successful responses as API errors", arguments: ["filename", "mime_type", "type", "wrong-type"])
    func uploadFileResponseValidation(invalidField: String) async throws {
        var payload: [String: JSONValue] = [
            "id": .string("file_invalid"), "type": .string("file"), "filename": .string("file.txt"),
            "mime_type": .string("text/plain"), "size_bytes": .number(4), "created_at": .string("2026-01-01T00:00:00Z"),
        ]
        if invalidField == "wrong-type" {
            payload["type"] = .string("message")
        } else {
            payload.removeValue(forKey: invalidField)
        }
        let responseData = try JSONEncoder().encode(payload)
        let provider: any ProviderV4 = createAnthropic(settings: .init(apiKey: "test-key", fetch: { request in
            FetchResponse(body: .data(responseData), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "application/json"]
            )!)
        }))

        do {
            _ = try await #require(try provider.files()).uploadFile(options: .init(data: .text("file"), mediaType: "text/plain"))
            Issue.record("Expected upload response rejection")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test("uploadFile maps anthropic provider metadata")
    func uploadFileMapsProviderMetadata() async throws {
        let capture = URLRequestCapture()
        let provider: any ProviderV4 = createAnthropic(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let result = try await #require(try provider.files()).uploadFile(
            options: .init(
                data: .base64("JVBERg=="),
                mediaType: "application/pdf"
            )
        )

        #expect(result.mediaType == "application/pdf")
        #expect(result.filename == "test.pdf")
        #expect(result.providerMetadata?["anthropic"]?["filename"] == .string("test.pdf"))
        #expect(result.providerMetadata?["anthropic"]?["mimeType"] == .string("application/pdf"))
        #expect(result.providerMetadata?["anthropic"]?["sizeBytes"] == .number(12_345))
        #expect(result.providerMetadata?["anthropic"]?["createdAt"] == .string("2025-04-14T12:00:00Z"))
        #expect(result.providerMetadata?["anthropic"]?["downloadable"] == .bool(true))
    }

    @Test("uploadFile accepts upstream text data variant")
    func uploadFileAcceptsTextDataVariant() async throws {
        let capture = URLRequestCapture()
        let provider: any ProviderV4 = createAnthropic(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        _ = try await #require(try provider.files()).uploadFile(
            options: .init(
                data: .text("plain text fixture"),
                mediaType: "text/plain",
                filename: "fixture.txt"
            )
        )

        guard let request = await capture.first(),
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundary = extractBoundary(from: contentType),
              let body = request.httpBody else {
            Issue.record("Missing multipart body")
            return
        }

        let parts = parseMultipart(body, boundary: boundary)
        let filePart = parts.first { multipartName($0) == "file" }

        #expect(multipartFilename(filePart!) == "fixture.txt")
        #expect(String(data: filePart?.body ?? Data(), encoding: .utf8) == "plain text fixture")
    }
}
