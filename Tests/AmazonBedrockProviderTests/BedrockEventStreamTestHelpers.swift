import Foundation
import AISDKProvider
import AISDKProviderUtils
import AmazonBedrockProvider
import Testing

actor BedrockTestServer {
    let body: Data
    let status: Int
    let headers: [String: String]
    private var captured: URLRequest?

    init(json: JSONValue = .object([
        "output": .object(["message": .object(["role": .string("assistant"), "content": .array([.object(["text": .string("ok")])])])]),
        "stopReason": .string("end_turn"), "usage": .object(["inputTokens": .number(1), "outputTokens": .number(2), "totalTokens": .number(3)])
    ]), status: Int = 200, headers: [String: String] = [:]) throws {
        self.body = try JSONEncoder().encode(json)
        self.status = status
        self.headers = headers
    }
    init(data: Data, status: Int = 200, headers: [String: String] = [:]) { self.body = data; self.status = status; self.headers = headers }
    nonisolated var fetch: FetchFunction {
        { request in
            await self.capture(request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: self.status, httpVersion: nil, headerFields: self.headers))
            return FetchResponse(body: .data(self.body), urlResponse: response)
        }
    }
    private func capture(_ request: URLRequest) { captured = request }
    func request() throws -> URLRequest { try #require(captured) }
    func requestBody() throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: try #require(captured?.httpBody)) }
    nonisolated func provider(region: String? = "us-east-1", baseURL: String? = "https://bedrock.test") -> AmazonBedrockProvider {
        createAmazonBedrock(settings: .init(region: region, apiKey: "test-key", baseURL: baseURL, fetch: fetch))
    }
}

extension JSONValue {
    subscript(_ key: String) -> JSONValue? { if case .object(let object) = self { return object[key] }; return nil }
    var array: [JSONValue] { if case .array(let array) = self { return array }; return [] }
}

enum BedrockTestEventStream {
    private static func u32be(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
    }

    private static func u16be(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
    }

    private static func stringHeader(name: String, value: String) -> Data {
        var data = Data()
        let nameBytes = Array(name.utf8)
        let valueBytes = Array(value.utf8)

        precondition(nameBytes.count <= 255, "Header name too long")
        data.append(UInt8(nameBytes.count))
        data.append(contentsOf: nameBytes)

        // header type: 7 = string
        data.append(UInt8(7))
        data.append(contentsOf: u16be(valueBytes.count))
        data.append(contentsOf: valueBytes)
        return data
    }

    static func frame(headers: [String: String], body: Data) -> Data {
        var headerData = Data()
        for (name, value) in headers {
            headerData.append(stringHeader(name: name, value: value))
        }

        let headersLength = headerData.count
        let totalLength = headersLength + body.count + 16

        var data = Data()
        data.reserveCapacity(totalLength)
        data.append(contentsOf: u32be(totalLength))
        data.append(contentsOf: u32be(headersLength))
        data.append(contentsOf: u32be(Int(crc32(data))))
        data.append(headerData)
        data.append(body)
        data.append(contentsOf: u32be(Int(crc32(data))))
        return data
    }

    static func jsonMessage(eventType: String, payload: Any) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        return frame(
            headers: [
                ":message-type": "event",
                ":event-type": eventType,
            ],
            body: body
        )
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }

    static func makeStream(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

