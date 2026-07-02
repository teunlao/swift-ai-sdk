import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

@Suite("AnthropicSkills")
struct AnthropicSkillsTests {
    private func makeFetch(capture: URLRequestCapture) -> FetchFunction {
        { request in
            await capture.append(request)

            let url = request.url?.absoluteString ?? ""
            let body: [String: Any]

            switch url {
            case "https://api.anthropic.com/v1/skills":
                body = [
                    "id": "skill_01Xud7kLMsjLfc7Aa6RvigZf",
                    "display_title": "Test Capture Skill",
                    "name": "test-capture-skill",
                    "description": "Old description",
                    "latest_version": "1772078378207930",
                    "source": "custom",
                    "created_at": "2026-02-26T03:59:39.314772Z",
                    "updated_at": "2026-02-26T03:59:39.314772Z"
                ]
            case "https://api.anthropic.com/v1/skills/skill_01Xud7kLMsjLfc7Aa6RvigZf/versions/1772078378207930":
                body = [
                    "type": "skill_version",
                    "skill_id": "skill_01Xud7kLMsjLfc7Aa6RvigZf",
                    "name": "test-capture-skill",
                    "description": "An updated test skill for fixture capture"
                ]
            default:
                body = [
                    "type": "error",
                    "error": [
                        "type": "not_found_error",
                        "message": "Not found"
                    ]
                ]
            }

            let statusCode = url.hasSuffix("/skills") || url.contains("/versions/") ? 200 : 404
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

    @Test("uploadSkill sends files and display title as multipart form data")
    func uploadSkillSendsMultipartFormData() async throws {
        let capture = URLRequestCapture()
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        _ = try await provider.skills().uploadSkill(
            options: SkillsV4UploadSkillCallOptions(
                files: [
                    SkillsV4File(
                        path: "index.ts",
                        content: SharedV4DataContent.data(Data("console.log('hello')".utf8))
                    )
                ],
                displayTitle: "My Custom Title"
            )
        )

        let requests = await capture.all()
        guard let createRequest = requests.first,
              let contentType = createRequest.value(forHTTPHeaderField: "Content-Type"),
              let boundary = extractBoundary(from: contentType),
              let body = createRequest.httpBody else {
            Issue.record("Missing skill upload request")
            return
        }

        let headers = createRequest.allHTTPHeaderFields ?? [:]
        #expect(headers["anthropic-beta"] == "skills-2025-10-02")
        #expect(headers["x-api-key"] == "test-api-key")

        let parts = parseMultipart(body, boundary: boundary)
        let titlePart = parts.first { multipartName($0) == "display_title" }
        let filePart = parts.first { multipartName($0) == "files[]" }

        #expect(String(data: titlePart?.body ?? Data(), encoding: .utf8) == "My Custom Title")
        #expect(multipartFilename(filePart!) == "index.ts")
    }

    @Test("uploadSkill maps response, version metadata, and provider metadata")
    func uploadSkillMapsResult() async throws {
        let capture = URLRequestCapture()
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let result = try await provider.skills().uploadSkill(
            options: SkillsV4UploadSkillCallOptions(
                files: [
                    SkillsV4File(
                        path: "index.ts",
                        content: SharedV4DataContent.base64("Y29uc29sZS5sb2coJ2hlbGxvJyk=")
                    )
                ]
            )
        )

        #expect(result.providerReference["anthropic"] == "skill_01Xud7kLMsjLfc7Aa6RvigZf")
        #expect(result.displayTitle == "Test Capture Skill")
        #expect(result.name == "test-capture-skill")
        #expect(result.description == "An updated test skill for fixture capture")
        #expect(result.latestVersion == "1772078378207930")
        #expect(result.providerMetadata?["anthropic"]?["source"] == JSONValue.string("custom"))
        #expect(result.providerMetadata?["anthropic"]?["createdAt"] == JSONValue.string("2026-02-26T03:59:39.314772Z"))
        #expect(result.providerMetadata?["anthropic"]?["updatedAt"] == JSONValue.string("2026-02-26T03:59:39.314772Z"))
        #expect(result.warnings.isEmpty)

        let requests = await capture.all()
        #expect(requests.count == 2)
        let versionHeaders = requests.last?.allHTTPHeaderFields ?? [:]
        #expect(versionHeaders["anthropic-beta"] == "skills-2025-10-02")
        #expect(versionHeaders["Content-Type"] == nil)
    }

    @Test("uploadSkill accepts upstream data initializer and text file data")
    func uploadSkillAcceptsDataInitializerAndTextFileData() async throws {
        let capture = URLRequestCapture()
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        _ = try await provider.skills().uploadSkill(
            options: SkillsV4UploadSkillCallOptions(
                files: [
                    SkillsV4File(
                        path: "README.md",
                        data: .text("# Skill\n")
                    )
                ]
            )
        )

        guard let createRequest = await capture.first(),
              let contentType = createRequest.value(forHTTPHeaderField: "Content-Type"),
              let boundary = extractBoundary(from: contentType),
              let body = createRequest.httpBody else {
            Issue.record("Missing skill upload request")
            return
        }

        let parts = parseMultipart(body, boundary: boundary)
        let filePart = parts.first { multipartName($0) == "files[]" }

        #expect(multipartFilename(filePart!) == "README.md")
        #expect(String(data: filePart?.body ?? Data(), encoding: .utf8) == "# Skill\n")
    }
}
