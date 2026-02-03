import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GroqProvider

@Suite("GroqTranscriptionModel")
struct GroqTranscriptionModelTests {
    private actor RequestCapture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func value() -> URLRequest? { request }
    }

    private func makeConfig(fetch: @escaping FetchFunction, currentDate: @escaping @Sendable () -> Date = { Date() }) -> GroqTranscriptionModel.Config {
        GroqTranscriptionModel.Config(
            provider: "groq.transcription",
            url: { _ in "https://api.groq.com/openai/v1/audio/transcriptions" },
            headers: { ["Authorization": "Bearer test"] },
            fetch: fetch,
            currentDate: currentDate
        )
    }

    private func makeResponse(headers: [String: String]? = nil) -> (FetchFunction, [SharedV3Warning]) {
        let responseJSON: [String: Any] = [
            "text": "Hello world!",
            "language": "en",
            "duration": 2.5,
            "segments": [[
                "text": "Hello world!",
                "start": 0.0,
                "end": 2.5
            ]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers ?? ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        return (fetch, [])
    }

    private func decodeMultipart(_ data: Data, boundary: String) -> [String: Any] {
        guard let body = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: Any] = [:]
        let parts = body.split(separator: "--\(boundary)")
        for part in parts {
            if part.isEmpty { continue }
            if part.hasPrefix("--") { continue }
            let sections = part.split(separator: "\r\n\r\n", maxSplits: 1)
            if sections.count != 2 { continue }
            let headers = sections[0]
            let value = sections[1].replacingOccurrences(of: "\r\n", with: "")
            if let nameRange = headers.range(of: "name=\""), let endRange = headers[nameRange.upperBound...].firstIndex(of: "\"") {
                let name = String(headers[nameRange.upperBound..<endRange])
                result[name] = value
            }
        }
        return result
    }

    @Test("passes model and audio multipart")
    func requestPayload() async throws {
        let capture = RequestCapture()
        let (fetch, _) = makeResponse()
        let captureFetch: FetchFunction = { request in
            await capture.store(request)
            return try await fetch(request)
        }

        let model = GroqTranscriptionModel(
            modelId: GroqTranscriptionModelId(rawValue: "whisper-large-v3"),
            config: makeConfig(fetch: captureFetch)
        )

        let audioData = Data([0x01, 0x02])
        _ = try await model.doGenerate(options: .init(audio: .binary(audioData), mediaType: "audio/wav"))

        guard let request = await capture.value(),
              let body = request.httpBody,
              let contentType = request.value(forHTTPHeaderField: "Content-Type") else {
            Issue.record("Missing request")
            return
        }

        guard let boundaryRange = contentType.range(of: "boundary=") else {
            Issue.record("Missing boundary")
            return
        }
        let boundary = String(contentType[boundaryRange.upperBound...])
        let parsed = decodeMultipart(body, boundary: boundary)
        #expect(parsed["model"] as? String == "whisper-large-v3")
    }

    @Test("includes custom headers")
    func requestHeaders() async throws {
        let capture = RequestCapture()
        let (fetch, _) = makeResponse()
        let captureFetch: FetchFunction = { request in
            await capture.store(request)
            return try await fetch(request)
        }

        let provider = GroqTranscriptionModel(
            modelId: GroqTranscriptionModelId(rawValue: "whisper-large-v3"),
            config: makeConfig(fetch: captureFetch)
        )

        _ = try await provider.doGenerate(options: .init(
            audio: .binary(Data()),
            mediaType: "audio/wav",
            headers: ["Custom-Request-Header": "value"]
        ))

        if let headers = await capture.value()?.allHTTPHeaderFields {
            let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
            #expect(normalized["authorization"] == "Bearer test")
            #expect(normalized["custom-request-header"] == "value")
        } else {
            Issue.record("Missing headers")
        }
    }

    @Test("maps response data")
    func responseMapping() async throws {
        let (fetch, _) = makeResponse()
        let model = GroqTranscriptionModel(
            modelId: GroqTranscriptionModelId(rawValue: "whisper-large-v3"),
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        #expect(result.text == "Hello world!")
        #expect(result.segments.count == 1)
        #expect(result.response.modelId == "whisper-large-v3")
    }

    @Test("uses injected current date for response")
    func responseUsesInjectedDate() async throws {
        let (fetch, _) = makeResponse(headers: ["X-Request-ID": "req-1"])
        let testDate = Date(timeIntervalSince1970: 0)
        let model = GroqTranscriptionModel(
            modelId: GroqTranscriptionModelId(rawValue: "whisper"),
            config: makeConfig(fetch: fetch, currentDate: { testDate })
        )

        let result = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        #expect(result.response.timestamp == testDate)
        if let headers = result.response.headers {
            let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
            #expect(normalized["x-request-id"] == "req-1")
        } else {
            Issue.record("Missing response headers")
        }
    }

    @Test("should use real date when no custom date provider is specified")
    func responseUsesRealDate() async throws {
        let (fetch, _) = makeResponse()
        let before = Date()

        let model = GroqTranscriptionModel(
            modelId: GroqTranscriptionModelId(rawValue: "whisper-large-v3-turbo"),
            config: makeConfig(fetch: fetch)  // No custom date provider
        )

        let result = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        let after = Date()

        #expect(result.response.timestamp >= before)
        #expect(result.response.timestamp <= after)
        #expect(result.response.modelId == "whisper-large-v3-turbo")
    }
}
