import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

@Suite("OpenAICompatibleImageModelV4")
struct OpenAICompatibleImageModelV4Tests {
    actor RequestCapture {
        private var request: URLRequest?

        func store(_ request: URLRequest) {
            self.request = request
        }

        func current() -> URLRequest? {
            request
        }
    }

    private let testDate = Date(timeIntervalSince1970: 1_704_067_200)

    private func makeResponseData(image: String = "base64-image") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": image]]
        ])
    }

    private func makeHTTPResponse(
        url: URL,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    @Test("generation uses native V4 provider namespace precedence and warnings")
    func generationUsesNativeV4ProviderNamespacePrecedenceAndWarnings() async throws {
        let capture = RequestCapture()
        let targetURL = URL(string: "https://api.example.com/images/generations")!
        let responseData = try makeResponseData()
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["X-Image": "generated"]
                )
            )
        }
        let model = OpenAICompatibleImageModelV4(
            modelId: .init(rawValue: "dall-e-3"),
            config: .init(
                provider: "black-forest-labs.image",
                headers: { ["Provider-Header": "provider"] },
                url: { options in "https://api.example.com\(options.path)" },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: "A geometric city",
            n: 2,
            size: "1024x1024",
            aspectRatio: "1:1",
            seed: 42,
            files: [],
            providerOptions: [
                "black-forest-labs": [
                    "quality": .string("raw"),
                    "response_format": .string("url")
                ],
                "blackForestLabs": [
                    "quality": .string("camel"),
                    "user": .string("user-123")
                ]
            ],
            headers: ["Request-Header": "request"]
        ))

        #expect(model.specificationVersion == "v4")
        #expect(model.provider == "black-forest-labs.image")
        #expect(model.modelId == "dall-e-3")
        if case .value(let count) = model.maxImagesPerCall {
            #expect(count == 10)
        } else {
            Issue.record("Expected a fixed V4 image call limit")
        }
        #expect(result.warnings == [
            .unsupported(
                feature: "aspectRatio",
                details: "This model does not support aspect ratio. Use `size` instead."
            ),
            .unsupported(feature: "seed", details: nil),
            .deprecated(
                setting: "providerOptions key 'black-forest-labs'",
                message: "Use 'blackForestLabs' instead."
            )
        ])
        #expect(result.images == .base64(["base64-image"]))
        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "dall-e-3")
        #expect(result.response.headers?["x-image"] == "generated")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing native V4 image generation request")
            return
        }

        let headers = Dictionary(uniqueKeysWithValues:
            (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }
        )
        #expect(request.url == targetURL)
        #expect(headers["provider-header"] == "provider")
        #expect(headers["request-header"] == "request")
        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == "A geometric city")
        #expect((json["n"] as? NSNumber)?.intValue == 2)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["quality"] as? String == "camel")
        #expect(json["user"] as? String == "user-123")
        #expect(json["response_format"] as? String == "b64_json")
    }

    @Test("editing sends binary URL and mask inputs as multipart form data")
    func editingSendsBinaryURLAndMaskInputsAsMultipartFormData() async throws {
        let capture = RequestCapture()
        let targetURL = URL(string: "https://api.example.com/images/edits")!
        let responseData = try makeResponseData(image: "edited-image")
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["X-Image": "edited"]
                )
            )
        }
        let model = OpenAICompatibleImageModelV4(
            modelId: .init(rawValue: "image-model"),
            config: .init(
                provider: "recraft.image",
                headers: { [:] },
                url: { options in "https://api.example.com\(options.path)" },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: "Combine and edit these images",
            n: 1,
            size: "512x512",
            files: [
                .file(
                    mediaType: "image/png",
                    data: .binary(Data("PNGDATA".utf8)),
                    providerOptions: nil
                ),
                .url(
                    url: "data:image/jpeg;base64,SlBFR0RBVEE=",
                    providerOptions: nil
                )
            ],
            mask: .file(
                mediaType: "image/png",
                data: .base64("TUFTSw=="),
                providerOptions: nil
            ),
            providerOptions: [
                "recraft": [
                    "quality": .string("hd"),
                    "steps": .number(20),
                    "user": .string("user-456")
                ]
            ]
        ))

        #expect(result.images == .base64(["edited-image"]))
        #expect(result.warnings.isEmpty)
        #expect(result.response.timestamp == testDate)
        #expect(result.response.headers?["x-image"] == "edited")

        guard let request = await capture.current(), let body = request.httpBody else {
            Issue.record("Missing native V4 image edit request")
            return
        }

        let headers = Dictionary(uniqueKeysWithValues:
            (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }
        )
        let contentType = headers["content-type"] ?? ""
        let bodyString = String(decoding: body, as: UTF8.self)

        #expect(request.url == targetURL)
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        #expect(bodyString.components(separatedBy: "name=\"image[]\"").count - 1 == 2)
        #expect(bodyString.contains("name=\"mask\""))
        #expect(bodyString.components(separatedBy: "filename=\"blob\"").count - 1 == 3)
        #expect(bodyString.lowercased().contains("content-type: image/png"))
        #expect(bodyString.lowercased().contains("content-type: image/jpeg"))
        #expect(bodyString.contains("PNGDATA"))
        #expect(bodyString.contains("JPEGDATA"))
        #expect(bodyString.contains("MASK"))
        #expect(bodyString.contains("name=\"model\""))
        #expect(bodyString.contains("image-model"))
        #expect(bodyString.contains("name=\"prompt\""))
        #expect(bodyString.contains("Combine and edit these images"))
        #expect(bodyString.contains("name=\"n\""))
        #expect(bodyString.contains("name=\"size\""))
        #expect(bodyString.contains("512x512"))
        #expect(bodyString.contains("name=\"quality\""))
        #expect(bodyString.contains("hd"))
        #expect(bodyString.contains("name=\"steps\""))
        #expect(bodyString.contains("20"))
        #expect(bodyString.contains("name=\"user\""))
        #expect(bodyString.contains("user-456"))
    }
}
