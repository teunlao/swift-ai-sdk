import Foundation

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
        // prelude CRC (ignored by decoder)
        data.append(contentsOf: u32be(0))
        data.append(headerData)
        data.append(body)
        // message CRC (ignored by decoder)
        data.append(contentsOf: u32be(0))
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

    static func makeStream(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

