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

    @Test("provider wires files and skills interfaces with upstream provider ids")
    func providerWiresInterfaces() {
        let provider = createAnthropicProvider(settings: .init(apiKey: "test-api-key"))

        #expect(provider.files().provider == "anthropic.messages")
        #expect(provider.files().specificationVersion == "v4")
        #expect(provider.skills().provider == "anthropic.skills")
        #expect(provider.skills().specificationVersion == "v4")
    }

    @Test("uploadFile sends multipart payload with anthropic files beta header")
    func uploadFileSendsMultipartPayload() async throws {
        let capture = URLRequestCapture()
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let result = try await provider.files().uploadFile(
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

    @Test("uploadFile maps anthropic provider metadata")
    func uploadFileMapsProviderMetadata() async throws {
        let capture = URLRequestCapture()
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let result = try await provider.files().uploadFile(
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
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        _ = try await provider.files().uploadFile(
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
