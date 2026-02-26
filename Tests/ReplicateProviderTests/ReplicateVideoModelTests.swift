import Foundation
import Testing
@testable import ReplicateProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils

private let prompt = "A rocket launching into space"

private struct MockMetrics: Sendable, Equatable {
    let predictTime: Double?

    func jsonObject() -> Any {
        [
            "predict_time": predictTime as Any
        ]
    }
}

private func headersLowercased(_ request: URLRequest) -> [String: String] {
    (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
        result[entry.key.lowercased()] = entry.value
    }
}

private func makeOptions(
    prompt: String? = prompt,
    n: Int = 1,
    image: VideoModelV3File? = nil,
    aspectRatio: String? = nil,
    resolution: String? = nil,
    duration: Int? = nil,
    fps: Int? = nil,
    seed: Int? = nil,
    providerOptions: SharedV3ProviderOptions? = [
        "replicate": [
            "pollIntervalMs": .number(10),
        ],
    ],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) -> VideoModelV3CallOptions {
    VideoModelV3CallOptions(
        prompt: prompt,
        n: n,
        aspectRatio: aspectRatio,
        resolution: resolution,
        duration: duration,
        fps: fps,
        seed: seed,
        image: image,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers
    )
}

private func createMockModel(
    modelId: String = "minimax/video-01",
    currentDate: (@Sendable () -> Date)? = nil,
    predictionId: String = "test-prediction-id",
    predictionStatus: String = "succeeded",
    output: String? = "https://replicate.delivery/video.mp4",
    error: String? = nil,
    pollsUntilDone: Int = 1,
    onRequest: (@Sendable (_ url: String, _ bodyData: Data?, _ headers: [String: String]) async -> Void)? = nil,
    apiToken: String = "test-api-token",
    metrics: MockMetrics? = MockMetrics(predictTime: 25.5)
) -> ReplicateVideoModel {
    actor PollState {
        var pollCount: Int = 0
        func next() -> Int {
            pollCount += 1
            return pollCount
        }
    }

    let pollState = PollState()

    let fetch: FetchFunction = { request in
        let urlString = request.url!.absoluteString

        if let onRequest {
            await onRequest(urlString, request.httpBody, headersLowercased(request))
        }

        func jsonResponse(_ json: Any, status: Int = 200) throws -> FetchResponse {
            let data = try JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        // Initial prediction request (POST)
        if urlString.contains("/predictions"),
           request.httpMethod != "GET",
           !urlString.contains(predictionId) {
            let isImmediate = pollsUntilDone == 0
            let statusValue = isImmediate ? predictionStatus : "starting"

            func anyOrNull(_ value: Any?) -> Any {
                value ?? NSNull()
            }

            return try jsonResponse([
                "id": predictionId,
                "status": statusValue,
                "output": isImmediate ? anyOrNull(output) : NSNull(),
                "error": isImmediate ? anyOrNull(error) : NSNull(),
                "urls": [
                    "get": "https://api.replicate.com/v1/predictions/\(predictionId)"
                ],
                "metrics": isImmediate ? anyOrNull(metrics?.jsonObject()) : NSNull(),
            ])
        }

        // Poll status request (GET)
        if urlString.contains("/predictions/\(predictionId)") {
            let pollCount = await pollState.next()

            if pollCount < pollsUntilDone {
                return try jsonResponse([
                    "id": predictionId,
                    "status": "processing",
                    "output": NSNull(),
                    "error": NSNull(),
                    "urls": [
                        "get": "https://api.replicate.com/v1/predictions/\(predictionId)"
                    ],
                    "metrics": NSNull(),
                ])
            }

            func anyOrNull(_ value: Any?) -> Any {
                value ?? NSNull()
            }

            return try jsonResponse([
                "id": predictionId,
                "status": predictionStatus,
                "output": anyOrNull(output),
                "error": anyOrNull(error),
                "urls": [
                    "get": "https://api.replicate.com/v1/predictions/\(predictionId)"
                ],
                "metrics": anyOrNull(metrics?.jsonObject()),
            ])
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        return FetchResponse(body: .data(Data("Not found".utf8)), urlResponse: response)
    }

    return ReplicateVideoModel(
        ReplicateVideoModelId(rawValue: modelId),
        config: ReplicateVideoModelConfig(
            provider: "replicate.video",
            baseURL: "https://api.replicate.com/v1",
            headers: { ["Authorization": "Bearer \(apiToken)"] },
            fetch: fetch,
            currentDate: currentDate ?? { Date() }
        )
    )
}

@Suite("ReplicateVideoModel")
struct ReplicateVideoModelTests {
    @Suite("constructor")
    struct ConstructorTests {
        @Test("should expose correct provider and model information")
        func exposesInformation() {
            let model = ReplicateVideoModel(
                "minimax/video-01",
                config: ReplicateVideoModelConfig(
                    provider: "replicate.video",
                    baseURL: "https://api.replicate.com/v1",
                    headers: { [:] },
                    fetch: nil
                )
            )

            #expect(model.provider == "replicate.video")
            #expect(model.modelId == "minimax/video-01")
            #expect(model.specificationVersion == "v3")

            if case .value(let value) = model.maxVideosPerCall {
                #expect(value == 1)
            } else {
                Issue.record("Expected maxVideosPerCall to be .value(1)")
            }
        }

        @Test("should support model IDs with versions")
        func supportsVersionedModelIds() {
            let model = ReplicateVideoModel(
                "stability-ai/stable-video-diffusion:abc123",
                config: ReplicateVideoModelConfig(
                    provider: "replicate.video",
                    baseURL: "https://api.replicate.com/v1",
                    headers: { [:] },
                    fetch: nil
                )
            )

            #expect(model.modelId == "stability-ai/stable-video-diffusion:abc123")
        }
    }

    @Suite("doGenerate")
    struct DoGenerateTests {
        @Test("should pass the correct parameters including prompt")
        func passPrompt() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions())

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured prediction body with input")
                return
            }

            #expect(input["prompt"] as? String == prompt)
        }

        @Test("should use /models/{modelId}/predictions for models without version")
        func unversionedPredictionUrl() async throws {
            actor Capture { var url: String?; func store(_ u: String) { url = u }; func value() -> String? { url } }
            let cap = Capture()

            let model = createMockModel(
                modelId: "minimax/video-01",
                pollsUntilDone: 0,
                onRequest: { url, _, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(url)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions())
            #expect(await cap.value() == "https://api.replicate.com/v1/models/minimax/video-01/predictions")
        }

        @Test("should use /predictions with version for models with version")
        func versionedPredictionUrlAndBody() async throws {
            actor Capture {
                var url: String?
                var bodyData: Data?
                func store(url: String, bodyData: Data?) { self.url = url; self.bodyData = bodyData }
                func value() -> (String?, Data?) { (url, bodyData) }
            }
            let cap = Capture()

            let model = createMockModel(
                modelId: "stability-ai/stable-video-diffusion:abc123",
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(url: url, bodyData: bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions())

            let captured = await cap.value()
            #expect(captured.0 == "https://api.replicate.com/v1/predictions")

            guard let data = captured.1,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Issue.record("Expected captured body")
                return
            }
            #expect(body["version"] as? String == "abc123")
        }

        @Test("should pass seed when provided")
        func passSeed() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(seed: 42))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["seed"] as? Int == 42)
        }

        @Test("should pass aspect ratio when provided")
        func passAspectRatio() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(aspectRatio: "16:9"))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["aspect_ratio"] as? String == "16:9")
        }

        @Test("should pass resolution as size when provided")
        func passResolution() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(resolution: "1920x1080"))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["size"] as? String == "1920x1080")
        }

        @Test("should pass duration when provided")
        func passDuration() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(duration: 5))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["duration"] as? Int == 5)
        }

        @Test("should pass fps when provided")
        func passFps() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(fps: 30))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["fps"] as? Int == 30)
        }

        @Test("should return video with correct data")
        func returnVideo() async throws {
            let model = createMockModel(output: "https://replicate.delivery/video-output.mp4", pollsUntilDone: 0)
            let result = try await model.doGenerate(options: makeOptions())

            #expect(result.videos.count == 1)
            #expect(result.videos.first == VideoModelV3VideoData.url(url: "https://replicate.delivery/video-output.mp4", mediaType: "video/mp4"))
            #expect(result.warnings == [])
        }
    }

    @Suite("response metadata")
    struct ResponseMetadataTests {
        @Test("should include timestamp and modelId in response")
        func includeTimestampAndModelId() async throws {
            let testDate = Date(timeIntervalSince1970: 0)
            let model = createMockModel(currentDate: { testDate }, pollsUntilDone: 0)
            let result = try await model.doGenerate(options: makeOptions())

            #expect(result.response.timestamp == testDate)
            #expect(result.response.modelId == "minimax/video-01")
        }
    }

    @Suite("providerMetadata")
    struct ProviderMetadataTests {
        @Test("should include prediction metadata")
        func includePredictionMetadata() async throws {
            let model = createMockModel(
                predictionId: "test-pred-123",
                pollsUntilDone: 0,
                metrics: MockMetrics(predictTime: 25.5)
            )

            let result = try await model.doGenerate(options: makeOptions())

            guard let meta = result.providerMetadata?["replicate"] else {
                Issue.record("Missing replicate provider metadata")
                return
            }

            #expect(meta["predictionId"] == JSONValue.string("test-pred-123"))

            if let metricsValue = meta["metrics"], case .object(let metricsObject) = metricsValue {
                #expect(metricsObject["predict_time"] == JSONValue.number(25.5))
            } else {
                Issue.record("Expected metrics object with predict_time")
            }
        }
    }

    @Suite("Image-to-Video")
    struct ImageToVideoTests {
        @Test("should send URL-based image directly")
        func urlImageDirect() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(
                image: .url(url: "https://example.com/image.png", providerOptions: nil)
            ))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["image"] as? String == "https://example.com/image.png")
        }

        @Test("should convert base64 image to data URI")
        func base64ImageToDataUri() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(
                pollsUntilDone: 0,
                onRequest: { url, bodyData, _ in
                    if url.contains("/predictions"), !url.contains("test-prediction") {
                        await cap.store(bodyData)
                    }
                }
            )

            _ = try await model.doGenerate(options: makeOptions(
                image: .file(mediaType: "image/png", data: .base64("base64-image-data"), providerOptions: nil)
            ))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["image"] as? String == "data:image/png;base64,base64-image-data")
        }
    }

    @Suite("Provider Options")
    struct ProviderOptionsTests {
        @Test("should pass guidance_scale option")
        func passGuidanceScale() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, bodyData, _ in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(bodyData)
                }
            })

            _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                "replicate": [
                    "pollIntervalMs": .number(10),
                    "guidance_scale": .number(7.5),
                ]
            ]))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["guidance_scale"] as? Double == 7.5)
        }

        @Test("should pass num_inference_steps option")
        func passNumInferenceSteps() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, bodyData, _ in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(bodyData)
                }
            })

            _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                "replicate": [
                    "pollIntervalMs": .number(10),
                    "num_inference_steps": .number(50),
                ]
            ]))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["num_inference_steps"] as? Int == 50)
        }

        @Test("should pass motion_bucket_id option")
        func passMotionBucketId() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, bodyData, _ in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(bodyData)
                }
            })

            _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                "replicate": [
                    "pollIntervalMs": .number(10),
                    "motion_bucket_id": .number(127),
                ]
            ]))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["motion_bucket_id"] as? Int == 127)
        }

        @Test("should pass prompt_optimizer option")
        func passPromptOptimizer() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, bodyData, _ in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(bodyData)
                }
            })

            _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                "replicate": [
                    "pollIntervalMs": .number(10),
                    "prompt_optimizer": .bool(true),
                ]
            ]))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["prompt_optimizer"] as? Bool == true)
        }

        @Test("should pass through custom options")
        func passThroughCustomOptions() async throws {
            actor Capture { var bodyData: Data?; func store(_ d: Data?) { bodyData = d }; func value() -> Data? { bodyData } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, bodyData, _ in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(bodyData)
                }
            })

            _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                "replicate": [
                    "pollIntervalMs": .number(10),
                    "custom_param": .string("custom_value"),
                ]
            ]))

            guard let data = await cap.value(),
                  let captured = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = captured["input"] as? [String: Any] else {
                Issue.record("Expected captured body with input")
                return
            }
            #expect(input["custom_param"] as? String == "custom_value")
        }

        @Test("should use maxWaitTimeInSeconds in prefer header")
        func maxWaitTimePreferHeader() async throws {
            actor Capture { var headers: [String: String] = [:]; func store(_ h: [String: String]) { headers = h }; func value() -> [String: String] { headers } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, _, headers in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(headers)
                }
            })

            _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                "replicate": [
                    "pollIntervalMs": .number(10),
                    "maxWaitTimeInSeconds": .number(30),
                ]
            ]))

            #expect(await cap.value()["prefer"] == "wait=30")
        }

        @Test("should use prefer: wait when maxWaitTimeInSeconds not provided")
        func defaultPreferHeader() async throws {
            actor Capture { var headers: [String: String] = [:]; func store(_ h: [String: String]) { headers = h }; func value() -> [String: String] { headers } }
            let cap = Capture()

            let model = createMockModel(pollsUntilDone: 0, onRequest: { url, _, headers in
                if url.contains("/predictions"), !url.contains("test-prediction") {
                    await cap.store(headers)
                }
            })

            _ = try await model.doGenerate(options: makeOptions())
            #expect(await cap.value()["prefer"] == "wait")
        }
    }

    @Suite("Error Handling")
    struct ErrorHandlingTests {
        @Test("should throw error when prediction fails")
        func predictionFailed() async {
            let model = createMockModel(
                predictionStatus: "failed",
                error: "Video generation failed: insufficient credits",
                pollsUntilDone: 0
            )

            do {
                _ = try await model.doGenerate(options: makeOptions())
                Issue.record("Expected error")
            } catch let error as any AISDKError {
                #expect(error.message.contains("insufficient credits"))
            } catch {
                Issue.record("Expected AISDKError, got: \(error)")
            }
        }

        @Test("should throw error when prediction is canceled")
        func predictionCanceled() async {
            let model = createMockModel(predictionStatus: "canceled", pollsUntilDone: 0)

            do {
                _ = try await model.doGenerate(options: makeOptions())
                Issue.record("Expected error")
            } catch let error as any AISDKError {
                #expect(error.message.lowercased().contains("canceled"))
            } catch {
                Issue.record("Expected AISDKError, got: \(error)")
            }
        }

        @Test("should throw error when no video URL in response")
        func noVideoUrl() async {
            let model = createMockModel(output: nil, pollsUntilDone: 0)

            do {
                _ = try await model.doGenerate(options: makeOptions())
                Issue.record("Expected error")
            } catch let error as any AISDKError {
                #expect(error.message == "No video URL in response")
            } catch {
                Issue.record("Expected AISDKError, got: \(error)")
            }
        }
    }

    @Suite("Polling Behavior")
    struct PollingBehaviorTests {
        @Test("should poll until prediction is done")
        func pollUntilDone() async throws {
            actor Counter { var value: Int = 0; func inc() { value += 1 }; func get() -> Int { value } }
            let counter = Counter()

            let model = createMockModel(
                pollsUntilDone: 3,
                onRequest: { url, _, _ in
                    if url.contains("/predictions/test-prediction-id") {
                        await counter.inc()
                    }
                }
            )

            let result = try await model.doGenerate(options: makeOptions())
            #expect(await counter.get() == 3)
            #expect(result.videos.count == 1)
        }

        @Test("should timeout after pollTimeoutMs")
        func timeoutAfterPollTimeout() async {
            let fetch: FetchFunction = { request in
                let urlString = request.url!.absoluteString
                if urlString.contains("/predictions") {
                    let body: [String: Any] = [
                        "id": "timeout-test",
                        "status": "processing",
                        "output": NSNull(),
                        "error": NSNull(),
                        "urls": [
                            "get": "https://api.replicate.com/v1/predictions/timeout-test"
                        ],
                        "metrics": NSNull(),
                    ]
                    let data = try JSONSerialization.data(withJSONObject: body)
                    let resp = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return FetchResponse(body: .data(data), urlResponse: resp)
                }
                let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                return FetchResponse(body: .data(Data()), urlResponse: resp)
            }

            let model = ReplicateVideoModel(
                "minimax/video-01",
                config: ReplicateVideoModelConfig(
                    provider: "replicate.video",
                    baseURL: "https://api.replicate.com/v1",
                    headers: { ["Authorization": "Bearer test-token"] },
                    fetch: fetch
                )
            )

            do {
                _ = try await model.doGenerate(options: makeOptions(providerOptions: [
                    "replicate": [
                        "pollIntervalMs": .number(10),
                        "pollTimeoutMs": .number(50),
                    ]
                ]))
                Issue.record("Expected timeout error")
            } catch let error as any AISDKError {
                #expect(error.message.lowercased().contains("timed out"))
            } catch {
                Issue.record("Expected AISDKError, got: \(error)")
            }
        }

        @Test("should respect abort signal")
        func respectAbortSignal() async {
            final class AbortFlag: @unchecked Sendable {
                private let lock = NSLock()
                private var aborted: Bool = false

                func abort() {
                    lock.lock()
                    aborted = true
                    lock.unlock()
                }

                func isAborted() -> Bool {
                    lock.lock()
                    let value = aborted
                    lock.unlock()
                    return value
                }
            }

            let flag = AbortFlag()

            let fetch: FetchFunction = { request in
                let urlString = request.url!.absoluteString

                func jsonResponse(_ json: Any) throws -> FetchResponse {
                    let data = try JSONSerialization.data(withJSONObject: json)
                    let resp = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return FetchResponse(body: .data(data), urlResponse: resp)
                }

                if urlString.contains("/predictions"), request.httpMethod != "GET" {
                    return try jsonResponse([
                        "id": "abort-test",
                        "status": "processing",
                        "output": NSNull(),
                        "error": NSNull(),
                        "urls": [
                            "get": "https://api.replicate.com/v1/predictions/abort-test"
                        ],
                        "metrics": NSNull(),
                    ])
                }

                if urlString.contains("/predictions/abort-test") {
                    flag.abort()
                    return try jsonResponse([
                        "id": "abort-test",
                        "status": "processing",
                        "output": NSNull(),
                        "error": NSNull(),
                        "urls": [
                            "get": "https://api.replicate.com/v1/predictions/abort-test"
                        ],
                        "metrics": NSNull(),
                    ])
                }

                let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                return FetchResponse(body: .data(Data()), urlResponse: resp)
            }

            let model = ReplicateVideoModel(
                "minimax/video-01",
                config: ReplicateVideoModelConfig(
                    provider: "replicate.video",
                    baseURL: "https://api.replicate.com/v1",
                    headers: { ["Authorization": "Bearer test-token"] },
                    fetch: fetch
                )
            )

            do {
                _ = try await model.doGenerate(options: makeOptions(
                    providerOptions: [
                        "replicate": [
                            "pollIntervalMs": .number(10),
                        ]
                    ],
                    abortSignal: { flag.isAborted() }
                ))
                Issue.record("Expected abort error")
            } catch let error as any AISDKError {
                #expect(error.message.lowercased().contains("aborted"))
            } catch {
                Issue.record("Expected AISDKError, got: \(error)")
            }
        }

        @Test("should handle immediate success (pollsUntilDone=0)")
        func immediateSuccess() async throws {
            let model = createMockModel(output: "https://replicate.delivery/immediate-video.mp4", pollsUntilDone: 0)
            let result = try await model.doGenerate(options: makeOptions())
            #expect(result.videos.first == VideoModelV3VideoData.url(url: "https://replicate.delivery/immediate-video.mp4", mediaType: "video/mp4"))
        }
    }

    @Suite("Media Type")
    struct MediaTypeTests {
        @Test("should always return video/mp4 as media type")
        func alwaysMp4() async throws {
            let model = createMockModel(output: "https://replicate.delivery/video.mp4", pollsUntilDone: 0)
            let result = try await model.doGenerate(options: makeOptions())
            #expect(result.videos.first == VideoModelV3VideoData.url(url: "https://replicate.delivery/video.mp4", mediaType: "video/mp4"))
        }
    }
}
