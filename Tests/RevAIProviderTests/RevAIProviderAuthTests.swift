import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import RevAIProvider

@Suite("RevAIProvider auth behavior", .serialized)
struct RevAIProviderAuthTests {
    @Test("supports upstream createRevai alias")
    func supportsCreateRevaiAlias() {
        let provider = createRevai(settings: RevAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.transcription(.machine)
        #expect(model.provider == "revai.transcription")
    }

    @Test("missing API key throws LoadAPIKeyError at request time")
    func missingAPIKeyThrowsAtRequestTime() async throws {
        actor RequestCapture {
            var requests: [URLRequest] = []
            func append(_ request: URLRequest) { requests.append(request) }
            func count() -> Int { requests.count }
        }

        let original = getenv("REVAI_API_KEY").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("REVAI_API_KEY", original, 1)
            } else {
                unsetenv("REVAI_API_KEY")
            }
        }

        unsetenv("REVAI_API_KEY")

        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = request.url ?? URL(string: "https://api.rev.ai/speechtotext/v1/jobs")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(Data("{}".utf8)), urlResponse: response)
        }

        let provider = createRevai(settings: RevAIProviderSettings(fetch: fetch))
        let model = provider.transcription(.machine)

        do {
            _ = try await model.doGenerate(options: .init(
                audio: .binary(Data([0x01])),
                mediaType: "audio/wav"
            ))
            Issue.record("Expected missing API key error")
        } catch let error as LoadAPIKeyError {
            #expect(error.message.contains("REVAI_API_KEY environment variable"))
        } catch {
            Issue.record("Expected LoadAPIKeyError, got: \(error)")
        }

        #expect(await capture.count() == 0)
    }
}
