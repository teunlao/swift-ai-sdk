import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import RevAIProvider

@Suite("RevAITranscriptionModel")
struct RevAITranscriptionModelTests {
    private actor RequestCapture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func first() -> URLRequest? { requests.first }
    }

    private struct MultipartPart {
        let headers: [String: String]
        let body: Data
    }

    private func extractBoundary(from contentType: String) -> String? {
        guard let range = contentType.range(of: "boundary=") else { return nil }
        let tail = contentType[range.upperBound...]
        return tail.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "\t" }).first.map(String.init)
    }

    private func parseMultipart(_ data: Data, boundary: String) -> [MultipartPart] {
        let bytes = [UInt8](data)
        let boundaryBytes = Array("--\(boundary)".utf8)

        guard !boundaryBytes.isEmpty, bytes.count >= boundaryBytes.count else { return [] }

        var positions: [Int] = []
        var i = 0
        while i <= bytes.count - boundaryBytes.count {
            var match = true
            for j in 0..<boundaryBytes.count {
                if bytes[i + j] != boundaryBytes[j] {
                    match = false
                    break
                }
            }
            if match {
                positions.append(i)
                i += boundaryBytes.count
            } else {
                i += 1
            }
        }

        guard positions.count >= 2 else { return [] }

        var parts: [MultipartPart] = []

        for index in 0..<(positions.count - 1) {
            let start = positions[index] + boundaryBytes.count
            let end = positions[index + 1]
            if start >= end { continue }

            var partStart = start
            if partStart + 1 < end, bytes[partStart] == 0x0d, bytes[partStart + 1] == 0x0a {
                partStart += 2
            }
            var partEnd = end
            if partEnd - 2 >= partStart, bytes[partEnd - 2] == 0x0d, bytes[partEnd - 1] == 0x0a {
                partEnd -= 2
            }
            if partStart >= partEnd { continue }

            let partBytes = Array(bytes[partStart..<partEnd])
            let partData = Data(partBytes)

            // Split headers/body on CRLFCRLF.
            let delimiter = Data([0x0d, 0x0a, 0x0d, 0x0a])
            guard let delimiterRange = partData.range(of: delimiter) else { continue }
            let headerData = partData.subdata(in: partData.startIndex..<delimiterRange.lowerBound)
            let bodyData = partData.subdata(in: delimiterRange.upperBound..<partData.endIndex)

            let headerString = String(data: headerData, encoding: .utf8) ?? ""
            var headers: [String: String] = [:]
            for rawLine in headerString.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let colonIndex = line.firstIndex(of: ":") else { continue }
                let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = value
            }

            parts.append(MultipartPart(headers: headers, body: bodyData))
        }

        return parts
    }

    private func partName(_ part: MultipartPart) -> String? {
        guard let contentDisposition = part.headers["content-disposition"] else { return nil }
        guard let nameRange = contentDisposition.range(of: "name=\"") else { return nil }
        let tail = contentDisposition[nameRange.upperBound...]
        guard let endQuote = tail.firstIndex(of: "\"") else { return nil }
        return String(tail[..<endQuote])
    }

    private func makeFetch(
        capture: RequestCapture,
        transcriptHeaders: [String: String]? = nil
    ) -> FetchFunction {
        let submitJSON = """
        {"id":"test-id","status":"in_progress","language":"en","created_on":"2018-05-05T23:23:22.29Z","transcriber":"machine"}
        """

        let pollJSON = """
        {"id":"test-id","status":"transcribed","language":"en","created_on":"2018-05-05T23:23:22.29Z","transcriber":"machine"}
        """

        let transcriptJSON = """
        {"monologues":[{"speaker":1,"elements":[{"type":"text","value":"Hello","ts":0.5,"end_ts":1.5,"confidence":1},{"type":"punct","value":" "},{"type":"text","value":"World","ts":1.75,"end_ts":2.85,"confidence":0.8},{"type":"punct","value":"."}]},{"speaker":2,"elements":[{"type":"text","value":"monologues","ts":3,"end_ts":3.5,"confidence":1},{"type":"punct","value":" "},{"type":"text","value":"are","ts":3.6,"end_ts":3.9,"confidence":1},{"type":"punct","value":" "},{"type":"text","value":"a","ts":4,"end_ts":4.3,"confidence":1},{"type":"punct","value":" "},{"type":"text","value":"block","ts":4.5,"end_ts":5.5,"confidence":1},{"type":"punct","value":" "},{"type":"text","value":"of","ts":5.75,"end_ts":6.14,"confidence":1},{"type":"punct","value":" "},{"type":"unknown","value":"<inaudible>"},{"type":"punct","value":" "},{"type":"text","value":"text","ts":6.5,"end_ts":7.78,"confidence":1},{"type":"punct","value":"."}]}]}
        """

        let makeResponse: @Sendable (_ url: String, _ statusCode: Int, _ headers: [String: String]?, _ body: Data) -> FetchResponse = { url, statusCode, headers, body in
            let httpResponse = HTTPURLResponse(
                url: URL(string: url)!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers ?? ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(body), urlResponse: httpResponse)
        }

        let submitData = Data(submitJSON.utf8)
        let pollData = Data(pollJSON.utf8)
        let transcriptData = Data(transcriptJSON.utf8)

        return { request in
            await capture.append(request)

            let url = request.url?.absoluteString ?? ""

            switch url {
            case "https://api.rev.ai/speechtotext/v1/jobs":
                return makeResponse(url, 200, nil, submitData)
            case "https://api.rev.ai/speechtotext/v1/jobs/test-id":
                return makeResponse(url, 200, nil, pollData)
            case "https://api.rev.ai/speechtotext/v1/jobs/test-id/transcript":
                return makeResponse(url, 200, transcriptHeaders ?? ["Content-Type": "application/json"], transcriptData)
            default:
                return makeResponse(url, 404, nil, Data("{\"error\":{\"message\":\"Not Found\",\"code\":404}}".utf8))
            }
        }
    }

    @Test("should pass the model")
    func passesModelInMultipart() async throws {
        let capture = RequestCapture()
        let fetch = makeFetch(capture: capture)

        let provider = createRevai(settings: .init(apiKey: "test-api-key", fetch: fetch))
        let model = provider.transcription(.machine)

        _ = try await model.doGenerate(options: .init(audio: .binary(Data([0x01, 0x02])), mediaType: "audio/wav"))

        guard let request = await capture.first(),
              let body = request.httpBody,
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              let boundary = extractBoundary(from: contentType)
        else {
            Issue.record("Missing request capture")
            return
        }

        let parts = parseMultipart(body, boundary: boundary)
        let byName = Dictionary(uniqueKeysWithValues: parts.compactMap { part in
            partName(part).map { ($0, part) }
        })

        guard let configPart = byName["config"] else {
            Issue.record("Missing config part")
            return
        }

        let configText = String(data: configPart.body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(configText == #"{"transcriber":"machine"}"#)

        guard let mediaPart = byName["media"] else {
            Issue.record("Missing media part")
            return
        }

        #expect(!mediaPart.body.isEmpty)
    }

    @Test("should pass headers")
    func passesHeaders() async throws {
        let capture = RequestCapture()
        let fetch = makeFetch(capture: capture)

        let provider = createRevAIProvider(settings: .init(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.transcription(modelId: .machine).doGenerate(
            options: .init(
                audio: .binary(Data([0x01])),
                mediaType: "audio/wav",
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let normalized = Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) })

        #expect(normalized["authorization"] == "Bearer test-api-key")
        #expect((normalized["content-type"] ?? "").hasPrefix("multipart/form-data; boundary="))
        #expect(normalized["custom-provider-header"] == "provider-header-value")
        #expect(normalized["custom-request-header"] == "request-header-value")

        #expect((normalized["user-agent"] ?? "").contains("ai-sdk/revai/"))
    }

    @Test("should extract the transcription text")
    func extractsTranscriptionText() async throws {
        let capture = RequestCapture()
        let fetch = makeFetch(capture: capture)

        let provider = createRevAIProvider(settings: .init(apiKey: "test-api-key", fetch: fetch))
        let model = provider.transcription("machine")

        let result = try await model.doGenerate(options: .init(audio: .binary(Data([0x01])), mediaType: "audio/wav"))

        #expect(result.text == "Hello World. monologues are a block of <inaudible> text.")
    }

    @Test("should include response data with timestamp, modelId and headers")
    func includesResponseMetadata() async throws {
        let capture = RequestCapture()
        let headers = [
            "Content-Type": "application/json",
            "x-request-id": "test-request-id",
            "x-ratelimit-remaining": "123",
        ]
        let fetch = makeFetch(capture: capture, transcriptHeaders: headers)

        let testDate = Date(timeIntervalSince1970: 0)
        let model = RevAITranscriptionModel(
            modelId: .machine,
            config: RevAIConfig(
                provider: "test-provider",
                url: { options in "https://api.rev.ai\(options.path)" },
                headers: { [:] },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: .init(audio: .binary(Data([0x01])), mediaType: "audio/wav"))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "machine")

        let responseHeaders = result.response.headers ?? [:]
        #expect(responseHeaders["content-type"] == "application/json")
        #expect(responseHeaders["x-request-id"] == "test-request-id")
        #expect(responseHeaders["x-ratelimit-remaining"] == "123")
    }
}
