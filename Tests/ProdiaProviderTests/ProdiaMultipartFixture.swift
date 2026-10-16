import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils

struct ProdiaMultipartFixture: Sendable {
    struct Part: Sendable {
        let name: String
        var filename: String? = nil
        let mediaType: String
        let data: Data
    }
    var job: String? = #"{"id":"job","created_at":"created","updated_at":"updated","config":{"seed":0},"metrics":{"elapsed":1.5,"ips":2},"price":{"product":"media","dollars":0.01}}"#
    let parts: [Part]

    func response(_ request: URLRequest) -> FetchResponse {
        var builder = MultipartFormDataBuilder(boundary: "prodia-fixture")
        if let job { builder.appendFile(name: "job", filename: "job.json", contentType: "application/json", data: Data(job.utf8)) }
        for part in parts { builder.appendFile(name: part.name, filename: part.filename, contentType: part.mediaType, data: part.data) }
        let multipart = builder.build()
        return .init(body: .data(multipart.data), urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": multipart.contentType, "x-request-id": "media-id"]
        )!)
    }

    static func requestJob(_ request: URLRequest) throws -> JSONValue {
        let boundary = try #require(request.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: "boundary=").last)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        let job = try #require(body.components(separatedBy: "--" + boundary).first { $0.contains("name=\"job\"") })
        let separator = try #require(job.range(of: "\r\n\r\n"))
        let text = job[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
