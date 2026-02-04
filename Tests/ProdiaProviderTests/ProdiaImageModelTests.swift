import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ProdiaProvider

@Suite("ProdiaImageModel")
struct ProdiaImageModelTests {
    private struct MultipartResponse: Sendable {
        let body: Data
        let contentType: String
    }

    private func createMultipartResponse(
        jobResult: [String: Any],
        imageContent: String = "test-binary-content"
    ) throws -> MultipartResponse {
        let boundary = "test-boundary-12345"
        let jobJsonData = try JSONSerialization.data(withJSONObject: jobResult)
        let imageBuffer = Data(imageContent.utf8)

        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"job\"; filename=\"job.json\"\r\n")
        append("Content-Type: application/json\r\n")
        append("\r\n")
        body.append(jobJsonData)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"output\"; filename=\"output.png\"\r\n")
        append("Content-Type: image/png\r\n")
        append("\r\n")
        body.append(imageBuffer)
        append("\r\n--\(boundary)--\r\n")

        return MultipartResponse(
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    private func makeModel(
        baseURL: String = "https://api.example.com/v2",
        headers: @escaping @Sendable () -> [String: String?] = { ["Authorization": "Bearer test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> ProdiaImageModel {
        ProdiaImageModel(
            modelId: .inferenceFluxFastSchnellTxt2imgV2,
            config: ProdiaImageModelConfig(
                provider: "prodia.image",
                baseURL: baseURL,
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    @Test("includes seed and steps when provided")
    func includesSeedAndSteps() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: 12345,
                providerOptions: ["prodia": ["steps": .number(4)]],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let config = json["config"] as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect((config["seed"] as? Double) == 12345)
        #expect((config["steps"] as? Double) == 4)
    }

    @Test("includes width and height when size is provided")
    func includesSizeWidthHeight() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: "1024x768",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let config = json["config"] as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect((config["width"] as? Double) == 1024)
        #expect((config["height"] as? Double) == 768)
    }

    @Test("provider options width/height take precedence over size")
    func providerOptionsPrecedence() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: "1024x768",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "prodia": [
                        "width": .number(512),
                        "height": .number(512),
                    ]
                ],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let config = json["config"] as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect((config["width"] as? Double) == 512)
        #expect((config["height"] as? Double) == 512)
    }

    @Test("includes style_preset when stylePreset is provided")
    func includesStylePreset() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "prodia": [
                        "stylePreset": .string("anime"),
                    ]
                ],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let config = json["config"] as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect((config["style_preset"] as? String) == "anime")
    }

    @Test("includes loras when provided")
    func includesLoras() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "prodia": [
                        "loras": .array([
                            .string("prodia/lora/flux/anime@v1"),
                            .string("prodia/lora/flux/realism@v1"),
                        ])
                    ]
                ],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let config = json["config"] as? [String: Any],
              let loras = config["loras"] as? [Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(loras.count == 2)
    }

    @Test("includes progressive when provided")
    func includesProgressive() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "prodia": [
                        "progressive": .bool(true),
                    ]
                ],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let config = json["config"] as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect((config["progressive"] as? Bool) == true)
    }

    @Test("calls the correct endpoint")
    func callsCorrectEndpoint() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.example.com/v2/job")
    }

    @Test("sends Accept: multipart/form-data header")
    func sendsAcceptHeader() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        #expect(headers["accept"] == "multipart/form-data; image/png")
    }

    @Test("merges provider and request headers")
    func mergesHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(
            headers: {
                [
                    "Custom-Provider-Header": "provider-header-value",
                    "Authorization": "Bearer test-key",
                ]
            },
            fetch: fetch
        )

        _ = try await model.doGenerate(
            options: .init(
                prompt: "p",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: ["Custom-Request-Header": "request-header-value"],
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["authorization"] == "Bearer test-key")
        #expect(headers["accept"] == "multipart/form-data; image/png")
    }

    @Test("returns image bytes from multipart response")
    func returnsImageBytes() async throws {
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))

        switch result.images {
        case .binary(let images):
            #expect(images.count == 1)
            #expect(String(data: images[0], encoding: .utf8) == "test-binary-content")
        default:
            Issue.record("Expected binary images")
        }
    }

    @Test("returns provider metadata from job result")
    func returnsProviderMetadata() async throws {
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "created_at": "2025-01-01T00:00:00Z",
            "updated_at": "2025-01-01T00:00:05Z",
            "state": ["current": "completed"],
            "config": ["prompt": "p", "seed": 42],
            "metrics": ["elapsed": 2.5, "ips": 10.5],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))

        guard let prodia = result.providerMetadata?["prodia"] else {
            Issue.record("Missing provider metadata")
            return
        }

        #expect(prodia.images == [
            .object([
                "jobId": .string("job-123"),
                "seed": .number(42),
                "elapsed": .number(2.5),
                "iterationsPerSecond": .number(10.5),
                "createdAt": .string("2025-01-01T00:00:00Z"),
                "updatedAt": .string("2025-01-01T00:00:05Z"),
            ])
        ])
    }

    @Test("omits optional metadata fields when not present in job result")
    func omitsOptionalMetadataFields() async throws {
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-456",
            "state": ["current": "completed"],
            "config": ["prompt": "p"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))

        guard let prodia = result.providerMetadata?["prodia"] else {
            Issue.record("Missing provider metadata")
            return
        }

        #expect(prodia.images == [
            .object([
                "jobId": .string("job-456"),
            ])
        ])
    }

    @Test("warns on invalid size format")
    func warnsOnInvalidSize() async throws {
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-456",
            "state": ["current": "completed"],
            "config": ["prompt": "p"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": multipart.contentType]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(
            options: .init(
                prompt: "p",
                n: 1,
                size: "invalid",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:]
            )
        )

        #expect(result.warnings == [
            .unsupported(
                feature: "size",
                details: "Invalid size format: invalid. Expected format: WIDTHxHEIGHT (e.g., 1024x1024)"
            )
        ])
    }

    @Test("handles API errors")
    func handlesAPIErrors() async throws {
        let responseJSON: [String: Any] = [
            "message": "Invalid prompt",
            "detail": "Prompt cannot be empty",
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch let error as APICallError {
            #expect(error.message == "Prompt cannot be empty")
            #expect(error.statusCode == 400)
            #expect(error.url == "https://api.example.com/v2/job")
        }
    }

    @Test("includes timestamp, headers, and modelId in response metadata")
    func includesResponseMetadata() async throws {
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": multipart.contentType,
                "x-request-id": "test-request-id",
            ]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let testDate = Date(timeIntervalSince1970: 0)
        let model = makeModel(fetch: fetch, currentDate: { testDate })

        let result = try await model.doGenerate(options: .init(prompt: "p", n: 1, providerOptions: [:]))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "inference.flux-fast.schnell.txt2img.v2")
        #expect(result.response.headers != nil)
    }

    @Test("constructor exposes correct provider and model information")
    func constructorInfo() {
        let model = makeModel()
        #expect(model.provider == "prodia.image")
        #expect(model.modelId == "inference.flux-fast.schnell.txt2img.v2")
        #expect(model.specificationVersion == "v3")
        switch model.maxImagesPerCall {
        case .value(let value):
            #expect(value == 1)
        default:
            Issue.record("Expected maxImagesPerCall = .value(1)")
        }
    }
}
