import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import FireworksProvider

@Suite("Fireworks image contracts")
struct FireworksImageModelTests {
    private actor PollState {
        var pending = true
        func status() -> String { if pending { pending = false; return "Pending" }; return "Ready" }
    }
    private final class Resource: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func release() { lock.withLock { cancelled = true } }
        var released: Bool { lock.withLock { cancelled } }
    }
    private func response(_ request: URLRequest, _ value: JSONValue, headers: [String: String] = [:]) throws -> FetchResponse {
        FetchResponse(body: .data(try JSONEncoder().encode(value)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"].merging(headers) { _, new in new })!)
    }
    private func image(fetch: @escaping FetchFunction, timeout: Int = 120000) -> FireworksImageModel {
        FireworksImageModel(modelId: .fluxKontextPro, config: .init(provider: "fireworks.image", baseURL: "https://api.example.com", headers: { ["Authorization": "Bearer config", "Cookie": "provider-cookie", "X-Provider": "provider", "User-Agent": "custom-agent"] }, fetch: fetch, pollIntervalMillis: 0, pollTimeoutMillis: timeout, currentDate: { Date(timeIntervalSince1970: 1234) }))
    }

    @Test("Kontext submits image editing, polls Pending to Ready and downloads the result")
    func asyncEditing() async throws {
        let state = PollState()
        let model = image(fetch: { request in
            if request.httpMethod == "GET" {
                #expect(request.url?.absoluteString == "https://cdn.example.org/image.png")
                #expect(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == Set(["user-agent"]))
                #expect(request.fetchRedirectMode == .manual)
                return FetchResponse(body: .data(Data([1, 2, 3])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Image": "download"])!)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer request")
            #expect(request.value(forHTTPHeaderField: "X-Caller") == "caller")
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            if request.url?.path.hasSuffix("/get_result") == true {
                #expect(body == ["id": .string("job")])
                let status = await state.status()
                return try response(request, .object(["id": .string("job"), "status": .string(status), "result": status == "Ready" ? .object(["sample": .string("https://cdn.example.org/image.png")]) : .null]))
            }
            #expect(request.url?.absoluteString == "https://api.example.com/workflows/accounts/fireworks/models/flux-kontext-pro")
            #expect(body["input_image"] == .string("data:image/png;base64,AQID"))
            #expect(body["width"] == .string("32"))
            #expect(body["height"] == .string("64"))
            #expect(body["aspect_ratio"] == .string("1:1"))
            #expect(body["seed"] == .number(7))
            #expect(body["num_inference_steps"] == .number(4))
            #expect(body["safety_tolerance"] == .number(6))
            #expect(body["output_format"] == .string("png"))
            #expect(body["future_option"] == .object(["enabled": .bool(true)]))
            return try response(request, .object(["request_id": .string("job")]))
        })
        let result = try await model.doGenerate(options: .init(prompt: "edit", n: 1, size: "32x64", aspectRatio: "1:1", seed: 7, files: [.file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil), .url(url: "https://example.com/ignored.png", providerOptions: nil)], mask: .file(mediaType: "image/png", data: .binary(Data([4])), providerOptions: nil), providerOptions: ["fireworks": ["num_inference_steps": .number(4), "safety_tolerance": .number(6), "output_format": .string("png"), "future_option": .object(["enabled": .bool(true)])]], headers: ["Authorization": "Bearer request", "X-Caller": "caller"]))
        #expect(result.images == .binary([Data([1, 2, 3])]))
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 1234))
        #expect(result.response.headers?["x-image"] == "download")
        #expect(result.warnings.count == 3)
        #expect(Set(result.warnings.compactMap { if case .unsupported(let feature, _) = $0 { feature } else { nil } }) == Set(["size", "mask"]))
    }

    private static let syncModels: [(FireworksImageModelId, String, String)] = [
        (.flux1DevFP8, "/workflows/accounts/fireworks/models/flux-1-dev-fp8/text_to_image", "size"),
        (.playgroundV25_1024pxAesthetic, "/image_generation/accounts/fireworks/models/playground-v2-5-1024px-aesthetic", "aspectRatio"),
        ("custom-model", "/workflows/custom-model/text_to_image", "size")
    ]
    @Test("sync backends retain routing and size/aspect warnings", arguments: syncModels)
    func syncBackend(_ id: FireworksImageModelId, _ path: String, _ warning: String) async throws {
        let provider = createFireworks(settings: .init(apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/inference/v1\(path)")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["width"] == .string("100"))
            #expect(body["height"] == .string("200"))
            #expect(body["aspect_ratio"] == .string("1:1"))
            return FetchResponse(body: .data(Data([42])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }))
        let result = try await provider.image(modelId: id).doGenerate(options: .init(prompt: "draw", n: 1, size: "100x200", aspectRatio: "1:1"))
        #expect(result.images == .binary([Data([42])]))
        #expect(result.warnings.contains { if case .unsupported(let feature, _) = $0 { feature == warning } else { false } })
    }

    @Test("file and mask capabilities distinguish editable known and unknown models", arguments: [(FireworksImageModelId.fluxKontextMax, Optional(true)), (.flux1DevFP8, Optional(false)), ("custom-model", nil)])
    func capabilities(_ id: FireworksImageModelId, _ supported: Bool?) async throws {
        let model = createFireworks().image(modelId: id)
        #expect(try await model.supportsFileInputs == supported)
        #expect(try await model.supportsMaskInputs == (supported == nil ? nil : false))
    }

    private static let invalidOptions: [JSONObject] = [["safety_tolerance": .number(7)], ["num_inference_steps": .number(1.5)], ["output_format": .string("webp")], ["guidance_scale": .null]]
    @Test("invalid image options fail before HTTP", arguments: invalidOptions)
    func optionsValidation(_ options: JSONObject) async throws {
        let model = image(fetch: { _ in Issue.record("Invalid options must not send HTTP"); throw CancellationError() })
        await #expect(throws: InvalidArgumentError.self) { _ = try await model.doGenerate(options: .init(prompt: "draw", n: 1, providerOptions: ["fireworks": options])) }
    }

    @Test("async terminal statuses produce typed failures", arguments: ["Error", "Failed", "Ready"])
    func failedStatus(_ status: String) async throws {
        let model = image(fetch: { request in
            if request.url?.path.hasSuffix("/get_result") == true { return try response(request, .object(["id": .string("job"), "status": .string(status), "result": status == "Ready" ? .object([:]) : .null])) }
            return try response(request, .object(["request_id": .string("job")]))
        })
        await #expect(throws: status == "Ready" ? FireworksImageError.missingSample : .generationFailed(status: status)) { _ = try await model.doGenerate(options: .init(prompt: "draw", n: 1)) }
    }

    @Test("poll result is required and sample cannot be null", arguments: [#"{"id":"job","status":"Ready"}"#, #"{"id":"job","status":"Ready","result":{"sample":null}}"#])
    func malformedPoll(_ body: String) async throws {
        let model = image(fetch: { request in
            if request.url?.path.hasSuffix("/get_result") == true {
                return FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
            return try response(request, .object(["request_id": .string("job")]))
        })
        await #expect(throws: APICallError.self) { _ = try await model.doGenerate(options: .init(prompt: "draw", n: 1)) }
    }

    @Test("poll deadline cancels pending response headers and body", arguments: ["headers", "body"])
    func pendingPollTimeout(_ phase: String) async throws {
        let resource = Resource()
        let model = image(fetch: { request in
            if request.url?.path.hasSuffix("/get_result") != true { return try response(request, .object(["request_id": .string("job")])) }
            if phase == "headers" {
                do { try await Task.sleep(for: .seconds(1)) } catch { resource.release(); throw error }
                return try response(request, .object(["id": .string("job"), "status": .string("Ready"), "result": .object(["sample": .string("https://example.com/image.png")])]))
            }
            let source = AsyncThrowingStream<Data, Error>.makeStream()
            let fallback = Task {
                do { try await Task.sleep(for: .seconds(1)); source.continuation.yield(Data(#"{"id":"job","status":"Pending","result":null}"#.utf8)); source.continuation.finish() } catch {}
            }
            source.continuation.onTermination = { reason in if case .cancelled = reason { resource.release() }; fallback.cancel() }
            return FetchResponse(body: .stream(source.stream), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }, timeout: 100)
        await #expect(throws: FireworksImageError.timedOut(milliseconds: 100)) { _ = try await model.doGenerate(options: .init(prompt: "draw", n: 1)) }
        #expect(resource.released)
    }

    private final class AbortState: @unchecked Sendable {
        private let lock = NSLock()
        private var aborted = false
        func abort() { lock.withLock { aborted = true } }
        var requested: Bool { lock.withLock { aborted } }
    }

    @Test("caller abort at response handoff releases the returned body")
    func abortedResponseHandoff() async throws {
        let abort = AbortState()
        let resource = Resource()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        source.continuation.onTermination = { reason in if case .cancelled = reason { resource.release() } }
        defer { source.continuation.finish() }
        let model = image(fetch: { request in
            if request.url?.path.hasSuffix("/get_result") == true {
                abort.abort()
                return FetchResponse(body: .stream(source.stream), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
            return try response(request, .object(["request_id": .string("job")]))
        })
        await #expect(throws: CancellationError.self) { _ = try await model.doGenerate(options: .init(prompt: "draw", n: 1, abortSignal: { abort.requested })) }
        #expect(resource.released)
    }

    @Test("returned image redirects cannot reach an untrusted private host")
    func privateRedirect() async throws {
        let provider = createFireworks(settings: .init(apiKey: "key", baseURL: "https://api.example.com", headers: ["Cookie": "secret"], fetch: { request in
            if request.httpMethod == "GET" {
                #expect(request.url?.absoluteString == "https://api.example.com/image.png")
                #expect(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == Set(["user-agent"]))
                return FetchResponse(body: .data(Data()), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": "http://127.0.0.1:9090/private.png"])!)
            }
            if request.url?.path.hasSuffix("/get_result") == true { return try response(request, .object(["id": .string("job"), "status": .string("Ready"), "result": .object(["sample": .string("https://api.example.com/image.png")])])) }
            return try response(request, .object(["request_id": .string("job")]))
        }))
        await #expect(throws: DownloadError.self) { _ = try await provider.image(modelId: .fluxKontextPro).doGenerate(options: .init(prompt: "draw", n: 1)) }
    }

    private static let downloads: [(String, String)] = [("http://127.0.0.1:8080/v1", "http://127.0.0.1:8080/image.png"), ("https://api.example.com/v1", "https://cdn.example.org/image.png")]
    @Test("returned image downloads receive only User-Agent on same and foreign origins", arguments: downloads)
    func isolatedDownload(_ base: String, _ url: String) async throws {
        let provider = createFireworks(settings: .init(apiKey: "key", baseURL: base, headers: ["Cookie": "provider-cookie", "X-Api-Key": "secret", "X-Provider": "provider"], fetch: { request in
            if request.httpMethod == "GET" {
                #expect(request.url?.absoluteString == url)
                #expect(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == Set(["user-agent"]))
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("caller-agent") == true)
                #expect(request.fetchRedirectMode == .manual)
                return FetchResponse(body: .data(Data([1, 2, 3])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "caller-cookie")
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "secret")
            #expect(request.value(forHTTPHeaderField: "X-Caller") == "caller")
            if request.url?.path.hasSuffix("/get_result") == true { return try response(request, .object(["id": .string("job"), "status": .string("Ready"), "result": .object(["sample": .string(url)])])) }
            return try response(request, .object(["request_id": .string("job")]))
        }))
        let result = try await provider.image(modelId: .fluxKontextPro).doGenerate(options: .init(prompt: "draw", n: 1, headers: ["Cookie": "caller-cookie", "X-Caller": "caller", "uSeR-aGeNt": "caller-agent"]))
        #expect(result.images == .binary([Data([1, 2, 3])]))
    }
}
