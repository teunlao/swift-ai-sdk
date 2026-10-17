import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import XAIProvider

@Suite("XAIFiles")
struct XAIFilesTests {
    private func files(_ fetch: @escaping FetchFunction) throws -> XAIFiles {
        try #require(createXai(settings: .init(apiKey: "key", fetch: fetch)).files() as? XAIFiles)
    }
    private func response(_ request: URLRequest, _ text: String, type: String = "application/json") -> FetchResponse {
        FetchResponse(body: .data(Data(text.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!)
    }

    @Test("uploads inline data with fields before the file and returns provider metadata")
    func upload() async throws {
        let files = try files { request in
            #expect(request.url?.path == "/v1/files")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            let expiry = try #require(body.range(of: "name=\"expires_after\""))
            let file = try #require(body.range(of: "name=\"file\""))
            #expect(expiry.lowerBound < file.lowerBound)
            #expect(body.contains("filename=\"notes.txt\""))
            #expect(body.contains("hello"))
            return response(request, #"{"id":"file-1","filename":"stored.txt","bytes":5.5,"created_at":1000,"expires_at":4600,"purpose":"assistant","status":"ready"}"#)
        }
        let result = try await files.uploadFile(options: .init(data: .text("hello"), mediaType: "text/plain", filename: "notes.txt", providerOptions: ["xai": ["teamId": .string("team"), "expiresAfter": .number(3600)]]))
        #expect(result.providerReference == ["xai": "file-1"])
        #expect(result.filename == "stored.txt")
        #expect(result.mediaType == "text/plain")
        #expect(result.byteSize == 5.5)
        #expect(result.providerMetadata?["xai"]?["bytes"] == .number(5.5))
        #expect(result.createdAt == Date(timeIntervalSince1970: 1000))
        #expect(result.expiresAt == Date(timeIntervalSince1970: 4600))
        #expect(result.providerMetadata?["xai"]?["purpose"] == .string("assistant"))
    }

    @Test("uploads stream data as multipart without buffering it into httpBody")
    func streamingUpload() async throws {
        let files = try files { request in
            let stream = try #require(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 128)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? CancellationError() }
                if count == 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            let body = String(decoding: bytes, as: UTF8.self)
            #expect(body.contains("streamed-file"))
            let field = try #require(body.range(of: "name=\"team_id\""))
            let file = try #require(body.range(of: "name=\"file\""))
            #expect(field.lowerBound < file.lowerBound)
            return response(request, #"{"id":"stream-file"}"#)
        }
        let data = AsyncThrowingStream<Data, Error> { continuation in continuation.yield(Data("streamed-file".utf8)); continuation.finish() }
        let result = try await files.uploadFile(options: .init(data: .stream(data), mediaType: "text/plain", providerOptions: ["xai": ["teamId": .string("team")]]))
        #expect(result.providerReference == ["xai": "stream-file"])
    }

    @Test("validation failure releases an upload stream before any request")
    func rejectedStream() async throws {
        let cancellation = AsyncStream<Void>.makeStream()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        source.continuation.onTermination = { _ in cancellation.continuation.yield(()); cancellation.continuation.finish() }
        let files = try files { _ in Issue.record("Invalid options must not send HTTP"); throw CancellationError() }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await files.uploadFile(options: .init(data: .stream(source.stream), mediaType: "text/plain", providerOptions: ["xai": ["expiresAfter": .number(1)]]))
        }
        var iterator = cancellation.stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test("metadata, download and deletion use opaque encoded references")
    func operations() async throws {
        let files = try files { request in
            #expect(request.url?.absoluteString.hasPrefix("https://api.x.ai/v1/files/%252E%252E") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            if request.httpMethod == "DELETE" { return response(request, #"{"id":"..","deleted":true}"#) }
            if request.url?.path.hasSuffix("/content") == true {
                #expect(request.value(forHTTPHeaderField: "X-Caller") == "files-client")
                return response(request, "downloaded", type: "text/plain; charset=utf-8")
            }
            return response(request, #"{"id":"..","filename":"notes.txt","bytes":1e20,"created_at":1,"expires_at":2}"#)
        }
        let metadata = try await files.getFileMetadata(options: .init(file: ["xai": ".."]))
        #expect(metadata.filename == "notes.txt")
        #expect(metadata.byteSize == 1e20)
        #expect(metadata.providerMetadata?["xai"]?["bytes"] == .number(1e20))
        let download = try await files.downloadFile(options: .init(file: ["xai": ".."], headers: ["X-Caller": "files-client"]))
        var data = Data()
        for try await chunk in download.content { data.append(chunk) }
        #expect(data == Data("downloaded".utf8))
        #expect(download.mediaType == "text/plain")
        let deletion = try await files.deleteFile(options: .init(file: ["xai": ".."]))
        #expect(deletion.deleted)
        #expect(deletion.providerReference == ["xai": ".."])
        await #expect(throws: InvalidArgumentError.self) { _ = try await files.downloadFile(options: .init(file: ["other": "file"])) }
    }
}
