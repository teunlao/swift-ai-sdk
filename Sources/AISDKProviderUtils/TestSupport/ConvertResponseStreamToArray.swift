import Foundation

/**
 Collects the string chunks emitted by a `ProviderHTTPResponse` stream.

 Port of `@ai-sdk/provider-utils/src/test/convert-response-stream-to-array.ts`.
 */
public func convertResponseStreamToArray(
    _ response: ProviderHTTPResponse
) async throws -> [String] {
    switch response.body {
    case .none:
        throw ResponseStreamConversionError.missingBody

    case .data(let data):
        guard !data.isEmpty else {
            return []
        }

        return [decodeReplacingInvalidUTF8(Array(data))]

    case .stream(let stream):
        var buffer: [UInt8] = []
        var decodedChunks: [String] = []

        func drainBuffer(allowPartial: Bool) {
            var chunk = ""

            while !buffer.isEmpty {
                let lead = buffer[0]

                if lead < 0x80 {
                    chunk.unicodeScalars.append(UnicodeScalar(lead))
                    buffer.removeFirst()
                    continue
                }

                let (expectedLength, validation) = expectedSequenceLength(for: lead)

                guard expectedLength > 0 else {
                    chunk.append("\u{FFFD}")
                    buffer.removeFirst()
                    continue
                }

                if buffer.count < expectedLength {
                    if allowPartial {
                        break
                    } else {
                        chunk.append("\u{FFFD}")
                        buffer.removeAll(keepingCapacity: false)
                        break
                    }
                }

                let continuation = buffer[1..<expectedLength]
                guard validation(continuation) else {
                    chunk.append("\u{FFFD}")
                    buffer.removeFirst()
                    continue
                }

                if let scalar = decodeScalar(from: buffer.prefix(expectedLength)) {
                    chunk.unicodeScalars.append(scalar)
                    buffer.removeFirst(expectedLength)
                } else {
                    chunk.append("\u{FFFD}")
                    buffer.removeFirst()
                }
            }

            if !chunk.isEmpty {
                decodedChunks.append(chunk)
            }
        }

        do {
            for try await chunk in stream {
                buffer.append(contentsOf: chunk)
                drainBuffer(allowPartial: true)
            }
        } catch {
            throw error
        }

        drainBuffer(allowPartial: false)

        return decodedChunks
    }
}

enum ResponseStreamConversionError: Error {
    case missingBody
}

private func expectedSequenceLength(for lead: UInt8) -> (Int, (ArraySlice<UInt8>) -> Bool) {
    switch lead {
    case 0xC2...0xDF:
        return (2, { bytes in
            guard let first = bytes.first else { return false }
            return first & 0xC0 == 0x80
        })
    case 0xE0:
        return (3, { bytes in
            guard bytes.count >= 2 else { return false }
            let b1 = bytes[bytes.startIndex]
            let b2 = bytes[bytes.startIndex + 1]
            return (0xA0...0xBF).contains(b1) && (b2 & 0xC0 == 0x80)
        })
    case 0xE1...0xEC, 0xEE...0xEF:
        return (3, { bytes in
            guard bytes.count >= 2 else { return false }
            return bytes.allSatisfy { $0 & 0xC0 == 0x80 }
        })
    case 0xED:
        return (3, { bytes in
            guard bytes.count >= 2 else { return false }
            let b1 = bytes[bytes.startIndex]
            let b2 = bytes[bytes.startIndex + 1]
            return (0x80...0x9F).contains(b1) && (b2 & 0xC0 == 0x80)
        })
    case 0xF0:
        return (4, { bytes in
            guard bytes.count >= 3 else { return false }
            let b1 = bytes[bytes.startIndex]
            return (0x90...0xBF).contains(b1) && bytes.dropFirst().allSatisfy { $0 & 0xC0 == 0x80 }
        })
    case 0xF1...0xF3:
        return (4, { bytes in
            guard bytes.count >= 3 else { return false }
            return bytes.allSatisfy { $0 & 0xC0 == 0x80 }
        })
    case 0xF4:
        return (4, { bytes in
            guard bytes.count >= 3 else { return false }
            let b1 = bytes[bytes.startIndex]
            return (0x80...0x8F).contains(b1) && bytes.dropFirst().allSatisfy { $0 & 0xC0 == 0x80 }
        })
    default:
        return (0, { _ in false })
    }
}

private func decodeScalar(from bytes: ArraySlice<UInt8>) -> UnicodeScalar? {
    var iterator = bytes.makeIterator()
    var scalarDecoder = UTF8()

    switch scalarDecoder.decode(&iterator) {
    case .scalarValue(let scalar):
        return scalar
    case .emptyInput, .error:
        return nil
    }
}

private func decodeReplacingInvalidUTF8(_ bytes: [UInt8]) -> String {
    var iterator = bytes.makeIterator()
    var scalarDecoder = UTF8()
    var result = ""

    decoding: while true {
        switch scalarDecoder.decode(&iterator) {
        case .scalarValue(let scalar):
            result.unicodeScalars.append(scalar)
        case .emptyInput:
            break decoding
        case .error:
            result.append("\u{FFFD}")
        }
    }

    return result
}
