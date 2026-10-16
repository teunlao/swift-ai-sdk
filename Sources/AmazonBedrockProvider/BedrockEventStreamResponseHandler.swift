import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-event-stream-response-handler.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

public func createBedrockEventStreamResponseHandler<T>(
    chunkSchema: FlexibleSchema<T>
) -> ResponseHandler<AsyncThrowingStream<ParseJSONResult<T>, Error>> {
    { input in
        let response = input.response
        guard case .none = response.body else {
            let headers = extractResponseHeaders(from: response.httpResponse)
            let sourceStream = response.body.makeStream()

            let stream = AsyncThrowingStream<ParseJSONResult<T>, Error> { continuation in
                let task = Task {
                    do {
                        for try await message in decodeBedrockEventStream(sourceStream) {
                            try Task.checkCancellation()
                            try await process(message: message, schema: chunkSchema, continuation: continuation)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }

            return ResponseHandlerResult(
                value: stream,
                responseHeaders: headers
            )
        }

        throw EmptyResponseBodyError()
    }
}

func decodeBedrockEventStream(_ source: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<BedrockEventStreamMessage, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var decoder = BedrockEventStreamDecoder()
            do {
                for try await chunk in source {
                    try Task.checkCancellation()
                    try decoder.feed(chunk) { continuation.yield($0) }
                }
                try decoder.flush { continuation.yield($0) }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Message Processing

private func process<T>(
    message: BedrockEventStreamMessage,
    schema: FlexibleSchema<T>,
    continuation: AsyncThrowingStream<ParseJSONResult<T>, Error>.Continuation
) async throws {
    let eventType: String?
    switch message.headers[":message-type"] {
    case "event": eventType = message.headers[":event-type"]
    case "exception": eventType = message.headers[":exception-type"]
    default: eventType = nil
    }
    guard let eventType else { return }

    guard let bodyText = String(data: message.body, encoding: .utf8) else {
        let cause = NSError(
            domain: "amazon-bedrock.event-stream",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Unable to decode Bedrock event stream chunk as UTF-8 text."]
        )
        let error = JSONParseError(text: "<binary>", cause: cause)
        continuation.yield(.failure(error: error, rawValue: nil))
        return
    }

    let parsed = await safeParseJSON(ParseJSONOptions(text: bodyText))

    switch parsed {
    case .failure(let error, _):
        continuation.yield(.failure(error: error, rawValue: nil))
        return
    case .success(let jsonValue, _):
        var cleanedValue = jsonValue
        if case .object(var object) = cleanedValue {
            object.removeValue(forKey: "p")
            cleanedValue = .object(object)
        }

        let wrapped = JSONValue.object([eventType: cleanedValue])
        let foundation = jsonValueToFoundation(wrapped)
        let validation = await safeValidateTypes(
            ValidateTypesOptions(value: foundation, schema: schema)
        )

        switch validation {
        case .success(let value, let raw):
            continuation.yield(.success(value: value, rawValue: raw))
        case .failure(let error, let raw):
            continuation.yield(.failure(error: error, rawValue: raw))
        }
    }
}

// MARK: - Event Stream Decoder

struct BedrockEventStreamMessage: Sendable {
    let headers: [String: String]
    let body: Data
}

private enum BedrockEventStreamError: Error {
    case invalidFrame
    case unsupportedHeaderType(UInt8)
    case invalidHeader
}

private struct BedrockEventStreamDecoder {
    private var buffer = Data()

    mutating func feed(
        _ chunk: Data,
        onMessage: (BedrockEventStreamMessage) throws -> Void
    ) throws {
        buffer.append(chunk)

        while true {
            guard let message = try nextMessage() else { break }
            try onMessage(message)
        }
    }

    mutating func flush(
        onMessage: (BedrockEventStreamMessage) throws -> Void
    ) throws {
        while let message = try nextMessage() {
            try onMessage(message)
        }

        if !buffer.isEmpty {
            throw BedrockEventStreamError.invalidFrame
        }
    }

    private mutating func nextMessage() throws -> BedrockEventStreamMessage? {
        guard buffer.count >= 4 else { return nil }

        let totalLength = try readUInt32(from: buffer, offset: 0)
        guard totalLength >= 16 else { throw BedrockEventStreamError.invalidFrame }
        guard totalLength <= buffer.count else { return nil }
        guard bedrockCRC32(buffer.prefix(8)) == UInt32(try readUInt32(from: buffer, offset: 8)),
              bedrockCRC32(buffer.prefix(totalLength - 4)) == UInt32(try readUInt32(from: buffer, offset: totalLength - 4)) else {
            throw BedrockEventStreamError.invalidFrame
        }

        let headersLength = try readUInt32(from: buffer, offset: 4)
        let payloadLength = Int(totalLength) - Int(headersLength) - 16
        guard payloadLength >= 0 else { throw BedrockEventStreamError.invalidFrame }

        let headersStartOffset = 12
        let headersEndOffset = headersStartOffset + Int(headersLength)
        let payloadStartOffset = headersEndOffset
        let payloadEndOffset = payloadStartOffset + payloadLength
        guard payloadEndOffset + 4 <= Int(totalLength) else { throw BedrockEventStreamError.invalidFrame }

        let headersStart = buffer.index(buffer.startIndex, offsetBy: headersStartOffset)
        let headersEnd = buffer.index(buffer.startIndex, offsetBy: headersEndOffset)
        let payloadStart = buffer.index(buffer.startIndex, offsetBy: payloadStartOffset)
        let payloadEnd = buffer.index(buffer.startIndex, offsetBy: payloadEndOffset)

        let headerData = buffer.subdata(in: headersStart..<headersEnd)
        let payloadData = buffer.subdata(in: payloadStart..<payloadEnd)

        buffer.removeFirst(Int(totalLength))

        let headers = try parseHeaders(headerData)
        return BedrockEventStreamMessage(headers: headers, body: payloadData)
    }

    private func parseHeaders(_ data: Data) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count {
            guard index < bytes.count else { throw BedrockEventStreamError.invalidHeader }
            let nameLength = Int(bytes[index])
            index += 1
            guard index + nameLength <= bytes.count else { throw BedrockEventStreamError.invalidHeader }
            let nameData = Data(bytes[index..<index + nameLength])
            index += nameLength
            guard let name = String(data: nameData, encoding: .utf8) else { throw BedrockEventStreamError.invalidHeader }
            guard index < bytes.count else { throw BedrockEventStreamError.invalidHeader }
            let headerType = bytes[index]
            index += 1

            switch headerType {
            case 0: // bool true
                result[name] = "true"
            case 1: // bool false
                result[name] = "false"
            case 2: // byte
                index += 1
            case 3: // short
                index += 2
            case 4: // int
                index += 4
            case 5: // long
                index += 8
            case 6: // byte array
                guard index + 2 <= bytes.count else { throw BedrockEventStreamError.invalidHeader }
                let length = Int(readUInt16(from: bytes, offset: index))
                index += 2 + length
            case 7: // string
                guard index + 2 <= bytes.count else { throw BedrockEventStreamError.invalidHeader }
                let length = Int(readUInt16(from: bytes, offset: index))
                index += 2
                guard index + length <= bytes.count else { throw BedrockEventStreamError.invalidHeader }
                let valueData = Data(bytes[index..<index + length])
                index += length
                result[name] = String(data: valueData, encoding: .utf8) ?? ""
            case 8: // timestamp
                index += 8
            case 9: // uuid
                index += 16
            default:
                throw BedrockEventStreamError.unsupportedHeaderType(headerType)
            }
            guard index <= bytes.count else { throw BedrockEventStreamError.invalidHeader }
        }

        return result
    }
}

private func bedrockCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
    }
    return ~crc
}

// MARK: - Binary Helpers

private func readUInt32(from data: Data, offset: Int) throws -> Int {
    guard offset + 4 <= data.count else { throw BedrockEventStreamError.invalidFrame }
    var value: UInt32 = 0
    for i in 0..<4 {
        let index = data.index(data.startIndex, offsetBy: offset + i)
        value = (value << 8) | UInt32(data[index])
    }
    return Int(value)
}

private func readUInt16(from bytes: [UInt8], offset: Int) -> UInt16 {
    var value: UInt16 = 0
    value = (value << 8) | UInt16(bytes[offset])
    value = (value << 8) | UInt16(bytes[offset + 1])
    return value
}
