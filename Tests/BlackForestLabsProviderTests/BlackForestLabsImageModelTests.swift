import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import BlackForestLabsProvider

@Suite("BlackForestLabsImageModel")
struct BlackForestLabsImageModelTests {
    private func makeModel(
        modelId: BlackForestLabsImageModelId = "test-model",
        pollIntervalMillis: Int? = nil,
        pollTimeoutMillis: Int? = nil,
        headers: (@Sendable () -> [String: String?])? = { ["x-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> BlackForestLabsImageModel {
        BlackForestLabsImageModel(
            modelId: modelId,
            config: BlackForestLabsImageModelConfig(
                provider: "black-forest-labs.image",
                baseURL: "https://api.example.com/v1",
                headers: headers,
                fetch: fetch,
                pollIntervalMillis: pollIntervalMillis,
                pollTimeoutMillis: pollTimeoutMillis,
                currentDate: currentDate
            )
        )
    }

    @Test("passes correct parameters including aspect ratio and providerOptions")
    func passesParameters() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func all() -> [URLRequest] { calls }
        }

        let capture = Capture()

        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/png"]
                )!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: nil,
                aspectRatio: "16:9",
                seed: nil,
                providerOptions: [
                    "blackForestLabs": [
                        "promptUpsampling": .bool(true),
                        "unsupportedProperty": .string("value"),
                    ]
                ]
            )
        )

        let calls = await capture.all()
        guard let first = calls.first,
              let body = first.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing submit request capture")
            return
        }

        #expect(first.url?.absoluteString == "https://api.example.com/v1/test-model")
        #expect(json["prompt"] as? String == "A cute baby sea otter")
        #expect(json["aspect_ratio"] as? String == "16:9")
        #expect(json["prompt_upsampling"] as? Bool == true)
        #expect(json["unsupportedProperty"] == nil)
    }

    @Test("warns and derives aspect_ratio when size is provided")
    func warnsAndDerivesAspectRatioFromSize() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": ["sample": "https://api.example.com/image.png"],
        ])
        let imageBytes = Data([1, 2, 3])

        actor Capture {
            var aspectRatio: String?
            func store(aspectRatio: String?) { self.aspectRatio = aspectRatio }
            func currentAspectRatio() -> String? { aspectRatio }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                if let body = request.httpBody,
                   let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    await capture.store(aspectRatio: json["aspect_ratio"] as? String)
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            if url == "https://api.example.com/image.png" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/png"]
                )!
                return FetchResponse(body: .data(imageBytes), urlResponse: response)
            }
            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "p",
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:]
            )
        )

        #expect(result.warnings == [
            SharedV3Warning.unsupported(
                feature: "size",
                details: "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
            )
        ])

        #expect(await capture.currentAspectRatio() == "1:1")
    }

    @Test("throws when poll is Ready but sample is missing")
    func throwsWhenReadyMissingSample() async throws {
        let submitData = try JSONSerialization.data(withJSONObject: [
            "id": "req-123",
            "polling_url": "https://api.example.com/poll",
        ])

        let pollData = try JSONSerialization.data(withJSONObject: [
            "status": "Ready",
            "result": NSNull(),
        ])

        let fetch: FetchFunction = { request in
            let url = request.url!.absoluteString
            if url == "https://api.example.com/v1/test-model" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(submitData), urlResponse: response)
            }
            if url.hasPrefix("https://api.example.com/poll") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(pollData), urlResponse: response)
            }
            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(
                    prompt: "p",
                    n: 1,
                    size: nil,
                    aspectRatio: "1:1",
                    seed: nil,
                    providerOptions: [:]
                )
            )
        }
    }

    @Test("exposes correct provider and model information")
    func constructorMetadata() throws {
        let model = makeModel()
        #expect(model.provider == "black-forest-labs.image")
        #expect(model.modelId == "test-model")
        #expect(model.specificationVersion == "v3")
    }
}
