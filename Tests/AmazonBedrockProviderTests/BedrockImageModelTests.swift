import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import AmazonBedrockProvider

@Suite("BedrockImageModel")
struct BedrockImageModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private let prompt = "A cute baby sea otter"
    private let baseURL = "https://bedrock-runtime.us-east-1.amazonaws.com"
    private let modelId: BedrockImageModelId = "amazon.nova-canvas-v1:0"

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func httpResponse(
        for request: URLRequest,
        statusCode: Int = 200,
        headers: [String: String]
    ) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeModel(
        modelId: BedrockImageModelId = "amazon.nova-canvas-v1:0",
        headers: [String: String?] = [:],
        currentDate: @escaping @Sendable () -> Date = { Date() },
        fetch: @escaping FetchFunction
    ) -> BedrockImageModel {
        BedrockImageModel(
            modelId: modelId,
            config: BedrockImageModelConfig(
                baseURL: { baseURL },
                headers: { headers },
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private func makeResponseData(_ body: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private func requestBodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func makePNGData() -> Data { Data([137, 80, 78, 71]) }
    private func makeMaskData() -> Data { Data([255, 255, 255, 0]) }
    private func makeJPEGData() -> Data { Data([255, 216, 255, 224]) }

    @Test("doGenerate passes model/settings and maps text-to-image request body")
    func doGenerateTextToImageRequestBody() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["base64-image-1", "base64-image-2"]
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(
            modelId: modelId,
            headers: [
                "config-header": "config-value",
                "shared-header": "config-shared",
            ],
            fetch: fetch
        )

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            seed: 1234,
            providerOptions: [
                "bedrock": [
                    "negativeText": .string("bad"),
                    "quality": .string("premium"),
                    "cfgScale": .number(1.2),
                ]
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "TEXT_IMAGE")

        guard let textToImageParams = json["textToImageParams"] as? [String: Any],
              let imageGenerationConfig = json["imageGenerationConfig"] as? [String: Any]
        else {
            Issue.record("Expected textToImageParams/imageGenerationConfig")
            return
        }

        #expect(textToImageParams["text"] as? String == prompt)
        #expect(textToImageParams["negativeText"] as? String == "bad")

        #expect(imageGenerationConfig["width"] as? Double == 1024)
        #expect(imageGenerationConfig["height"] as? Double == 1024)
        #expect(imageGenerationConfig["seed"] as? Double == 1234)
        #expect(imageGenerationConfig["numberOfImages"] as? Double == 1)
        #expect(imageGenerationConfig["quality"] as? String == "premium")
        #expect(imageGenerationConfig["cfgScale"] as? Double == 1.2)
    }

    @Test("doGenerate properly combines headers from all sources")
    func doGenerateCombinesHeaders() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["base64-image-1"]
        ])

        let fetch: FetchFunction = { request in
            var request = request
            request.setValue("signed-value", forHTTPHeaderField: "signed-header")
            request.setValue("AWS4-HMAC-SHA256...", forHTTPHeaderField: "authorization")

            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(
            modelId: modelId,
            headers: [
                "model-header": "model-value",
                "shared-header": "model-shared",
            ],
            fetch: fetch
        )

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            headers: [
                "options-header": "options-value",
                "shared-header": "options-shared",
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(request)
        #expect(headers["options-header"] == "options-value")
        #expect(headers["model-header"] == "model-value")
        #expect(headers["signed-header"] == "signed-value")
        #expect(headers["authorization"] == "AWS4-HMAC-SHA256...")
        #expect(headers["shared-header"] == "options-shared")
    }

    @Test("maxImagesPerCall respects model settings")
    func maxImagesPerCallRespectsSettings() async throws {
        let provider = createAmazonBedrock()

        let defaultModel = provider.image(modelId: modelId)
        if case .value(let max) = defaultModel.maxImagesPerCall {
            #expect(max == 5)
        } else {
            Issue.record("Expected fixed maxImagesPerCall value for known model")
        }

        let unknownModel = provider.image(modelId: "unknown-model")
        if case .value(let max) = unknownModel.maxImagesPerCall {
            #expect(max == 1)
        } else {
            Issue.record("Expected fixed maxImagesPerCall value for unknown model")
        }
    }

    @Test("doGenerate returns warnings for unsupported settings")
    func doGenerateUnsupportedWarnings() async throws {
        let responseData = try makeResponseData([
            "images": ["base64-image-1", "base64-image-2"]
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            aspectRatio: "1:1"
        ))

        #expect(result.warnings == [
            .unsupported(
                feature: "aspectRatio",
                details: "This model does not support aspect ratio. Use `size` instead."
            )
        ])
    }

    @Test("doGenerate extracts generated images")
    func doGenerateExtractImages() async throws {
        let responseData = try makeResponseData([
            "images": ["base64-image-1", "base64-image-2"]
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: prompt, n: 1))

        guard case .base64(let images) = result.images else {
            Issue.record("Expected base64 images")
            return
        }

        #expect(images == ["base64-image-1", "base64-image-2"])
    }

    @Test("doGenerate includes response data with timestamp, modelId and headers")
    func doGenerateIncludesResponseInfo() async throws {
        let testDate = Date(timeIntervalSince1970: 1_710_504_000) // 2024-03-15T12:00:00Z

        let responseBody: [String: Any] = [
            "images": ["base64-image-1", "base64-image-2"]
        ]
        let responseData = try makeResponseData(responseBody)

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: [
                "Content-Type": "application/json",
                "Content-Length": "\(responseData.count)",
            ])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(
            modelId: modelId,
            currentDate: { testDate },
            fetch: fetch
        )

        let result = try await model.doGenerate(options: .init(prompt: prompt, n: 1, size: "1024x1024"))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == modelId.rawValue)
        #expect(result.response.headers?["content-type"] == "application/json")
        #expect(result.response.headers?["content-length"] == "\(responseData.count)")
    }

    @Test("doGenerate uses real date when no custom date provider is specified")
    func doGenerateUsesRealDateByDefault() async throws {
        let responseData = try makeResponseData([
            "images": ["base64-image-1"]
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        let before = Date()
        let result = try await model.doGenerate(options: .init(prompt: prompt, n: 1, seed: 1234))
        let after = Date()

        #expect(result.response.timestamp.timeIntervalSince1970 >= before.timeIntervalSince1970)
        #expect(result.response.timestamp.timeIntervalSince1970 <= after.timeIntervalSince1970)
        #expect(result.response.modelId == modelId.rawValue)
    }

    @Test("doGenerate passes style parameter when provided")
    func doGenerateStyleParameterIncluded() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["base64-image-1"]
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            seed: 1234,
            providerOptions: [
                "bedrock": [
                    "negativeText": .string("bad"),
                    "quality": .string("premium"),
                    "cfgScale": .number(1.2),
                    "style": .string("PHOTOREALISM"),
                ]
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        guard let textToImageParams = json["textToImageParams"] as? [String: Any] else {
            Issue.record("Expected textToImageParams")
            return
        }

        #expect(textToImageParams["style"] as? String == "PHOTOREALISM")
    }

    @Test("doGenerate does not include style when not provided")
    func doGenerateStyleParameterOmitted() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["base64-image-1"]
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            seed: 1234,
            providerOptions: [
                "bedrock": [
                    "quality": .string("standard"),
                ]
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        guard let textToImageParams = json["textToImageParams"] as? [String: Any] else {
            Issue.record("Expected textToImageParams")
            return
        }

        #expect(textToImageParams["style"] == nil)
    }

    @Test("doGenerate throws error when request is moderated")
    func doGenerateModeratedThrows() async throws {
        let responseData = try makeResponseData([
            "id": "fe7256d1-50d9-4663-8592-85eaf002e80c",
            "status": "Request Moderated",
            "result": NSNull(),
            "progress": NSNull(),
            "details": ["Moderation Reasons": ["Derivative Works Filter"]],
            "preview": NSNull(),
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: "Generate something that triggers moderation", n: 1))
            Issue.record("Expected error")
        } catch {
            #expect(error.localizedDescription == "Amazon Bedrock request was moderated: Derivative Works Filter")
        }
    }

    @Test("doGenerate throws error when no images are returned")
    func doGenerateNoImagesThrows() async throws {
        let responseData = try makeResponseData([
            "images": [],
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: "Generate an image", n: 1))
            Issue.record("Expected error")
        } catch {
            #expect(error.localizedDescription.contains("Amazon Bedrock returned no images"))
        }
    }

    // MARK: - Image Editing

    @Test("Image editing: inpainting with files + maskPrompt")
    func editInpaintingMaskPrompt() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "a cute corgi dog",
            n: 1,
            seed: 42,
            providerOptions: [
                "bedrock": [
                    "maskPrompt": .string("cat"),
                    "quality": .string("standard"),
                    "cfgScale": .number(7.0),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "INPAINTING")

        guard let inPaintingParams = json["inPaintingParams"] as? [String: Any],
              let imageGenerationConfig = json["imageGenerationConfig"] as? [String: Any]
        else {
            Issue.record("Expected inPaintingParams/imageGenerationConfig")
            return
        }

        #expect(inPaintingParams["image"] as? String == "iVBORw==")
        #expect(inPaintingParams["maskPrompt"] as? String == "cat")
        #expect(inPaintingParams["text"] as? String == "a cute corgi dog")

        #expect(imageGenerationConfig["seed"] as? Double == 42)
        #expect(imageGenerationConfig["numberOfImages"] as? Double == 1)
        #expect(imageGenerationConfig["quality"] as? String == "standard")
        #expect(imageGenerationConfig["cfgScale"] as? Double == 7.0)
    }

    @Test("Image editing: inpainting with files + mask image")
    func editInpaintingMaskImage() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "A sunlit indoor lounge area with a pool containing a flamingo",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "quality": .string("standard"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ],
            mask: .file(mediaType: "image/png", data: .binary(makeMaskData()), providerOptions: nil)
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "INPAINTING")

        guard let inPaintingParams = json["inPaintingParams"] as? [String: Any] else {
            Issue.record("Expected inPaintingParams")
            return
        }

        #expect(inPaintingParams["image"] as? String == "iVBORw==")
        #expect(inPaintingParams["maskImage"] as? String == "////AA==")
    }

    @Test("Image editing: inpainting with base64 string data")
    func editInpaintingBase64Data() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        let base64Image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"

        _ = try await model.doGenerate(options: .init(
            prompt: "Edit this image",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "maskPrompt": .string("background"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .base64(base64Image), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        guard let inPaintingParams = json["inPaintingParams"] as? [String: Any] else {
            Issue.record("Expected inPaintingParams")
            return
        }

        #expect(inPaintingParams["image"] as? String == base64Image)
    }

    @Test("Image editing: negativeText is included in inpainting params")
    func editInpaintingNegativeText() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "a beautiful garden",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "maskPrompt": .string("sky"),
                    "negativeText": .string("clouds, rain"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        guard let inPaintingParams = json["inPaintingParams"] as? [String: Any] else {
            Issue.record("Expected inPaintingParams")
            return
        }

        #expect(inPaintingParams["negativeText"] as? String == "clouds, rain")
    }

    @Test("Image editing: extracts edited images from response")
    func editExtractsImages() async throws {
        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        let result = try await model.doGenerate(options: .init(
            prompt: "Edit this image",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "maskPrompt": .string("object"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard case .base64(let images) = result.images else {
            Issue.record("Expected base64 images")
            return
        }

        #expect(images == ["edited-image-base64"])
    }

    @Test("Image editing: throws error for URL-based images")
    func editURLBasedImagesThrow() async throws {
        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(
                prompt: "Edit this image",
                n: 1,
                files: [
                    .url(url: "https://example.com/image.png", providerOptions: nil)
                ]
            ))
            Issue.record("Expected error")
        } catch {
            #expect(error.localizedDescription.contains("URL-based images are not supported for Amazon Bedrock image editing."))
        }
    }

    @Test("Image editing: outpainting request with taskType OUTPAINTING")
    func editOutpaintingMaskImage() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Extend the background with a beautiful sunset",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "taskType": .string("OUTPAINTING"),
                    "outPaintingMode": .string("DEFAULT"),
                    "negativeText": .string("bad quality"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ],
            mask: .file(mediaType: "image/png", data: .binary(makeMaskData()), providerOptions: nil)
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "OUTPAINTING")

        guard let outPaintingParams = json["outPaintingParams"] as? [String: Any] else {
            Issue.record("Expected outPaintingParams")
            return
        }

        #expect(outPaintingParams["image"] as? String == "iVBORw==")
        #expect(outPaintingParams["maskImage"] as? String == "////AA==")
        #expect(outPaintingParams["negativeText"] as? String == "bad quality")
        #expect(outPaintingParams["outPaintingMode"] as? String == "DEFAULT")
    }

    @Test("Image editing: outpainting request with maskPrompt")
    func editOutpaintingMaskPrompt() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Replace the background with mountains",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "taskType": .string("OUTPAINTING"),
                    "maskPrompt": .string("background"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "OUTPAINTING")

        guard let outPaintingParams = json["outPaintingParams"] as? [String: Any] else {
            Issue.record("Expected outPaintingParams")
            return
        }

        #expect(outPaintingParams["maskPrompt"] as? String == "background")
    }

    @Test("Image editing: background removal request")
    func editBackgroundRemoval() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: nil,
            n: 1,
            providerOptions: [
                "bedrock": [
                    "taskType": .string("BACKGROUND_REMOVAL"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "BACKGROUND_REMOVAL")
        #expect(json["imageGenerationConfig"] == nil)

        guard let params = json["backgroundRemovalParams"] as? [String: Any] else {
            Issue.record("Expected backgroundRemovalParams")
            return
        }

        #expect(params["image"] as? String == "iVBORw==")
    }

    @Test("Image editing: image variation with single image")
    func editImageVariationSingleImage() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Create a variation in anime style",
            n: 3,
            size: "512x512",
            providerOptions: [
                "bedrock": [
                    "taskType": .string("IMAGE_VARIATION"),
                    "similarityStrength": .number(0.7),
                    "negativeText": .string("bad quality, low resolution"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "IMAGE_VARIATION")

        guard let imageVariationParams = json["imageVariationParams"] as? [String: Any],
              let images = imageVariationParams["images"] as? [String],
              let imageGenerationConfig = json["imageGenerationConfig"] as? [String: Any]
        else {
            Issue.record("Expected imageVariationParams/images/imageGenerationConfig")
            return
        }

        #expect(images == ["iVBORw=="])
        #expect(imageVariationParams["negativeText"] as? String == "bad quality, low resolution")
        #expect(imageVariationParams["similarityStrength"] as? Double == 0.7)
        #expect(imageVariationParams["text"] as? String == "Create a variation in anime style")

        #expect(imageGenerationConfig["width"] as? Double == 512)
        #expect(imageGenerationConfig["height"] as? Double == 512)
        #expect(imageGenerationConfig["numberOfImages"] as? Double == 3)
    }

    @Test("Image editing: image variation with multiple images")
    func editImageVariationMultipleImages() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Combine these images into one cohesive scene",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "taskType": .string("IMAGE_VARIATION"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil),
                .file(mediaType: "image/jpeg", data: .binary(makeJPEGData()), providerOptions: nil),
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        guard let imageVariationParams = json["imageVariationParams"] as? [String: Any],
              let images = imageVariationParams["images"] as? [String]
        else {
            Issue.record("Expected imageVariationParams.images")
            return
        }

        #expect(images == ["iVBORw==", "/9j/4A=="])
    }

    @Test("Image editing: defaults to IMAGE_VARIATION when files provided without mask/maskPrompt")
    func editDefaultsToImageVariation() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Create variations",
            n: 1,
            providerOptions: [:],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "IMAGE_VARIATION")
    }

    @Test("Image editing: defaults to INPAINTING when files provided with mask")
    func editDefaultsToInpaintingWithMask() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Edit masked area",
            n: 1,
            providerOptions: [:],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ],
            mask: .file(mediaType: "image/png", data: .binary(makeMaskData()), providerOptions: nil)
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "INPAINTING")
    }

    @Test("Image editing: defaults to INPAINTING when files provided with maskPrompt")
    func editDefaultsToInpaintingWithMaskPrompt() async throws {
        let capture = RequestCapture()

        let responseData = try makeResponseData([
            "images": ["edited-image-base64"],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Edit the cat",
            n: 1,
            providerOptions: [
                "bedrock": [
                    "maskPrompt": .string("cat"),
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(makePNGData()), providerOptions: nil)
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let json = try requestBodyJSON(request)
        #expect(json["taskType"] as? String == "INPAINTING")
    }
}
