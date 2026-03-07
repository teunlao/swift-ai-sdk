import Foundation

/**
 Processes a byte stream and forwards decoded text chunks.

 Port of `@ai-sdk/ai/src/ui/process-text-stream.ts`.

 **Adaptations**:
 - TypeScript uses `ReadableStream<Uint8Array>` and `TextDecoderStream`.
 - Swift uses `AsyncThrowingStream<Data, Error>` and an incremental UTF-8 decoder
   so multibyte code points can span chunk boundaries safely.
 */
public func processTextStream(
    stream: AsyncThrowingStream<Data, Error>,
    onTextPart: @escaping @Sendable (String) async -> Void
) async throws {
    var decoder = UTF8ChunkDecoder()

    for try await chunk in stream {
        decoder.append(chunk)

        let decoded = decoder.decodeAvailable(allowPartial: true)
        if !decoded.isEmpty {
            await onTextPart(decoded)
        }
    }

    let trailing = decoder.decodeAvailable(allowPartial: false)
    if !trailing.isEmpty {
        await onTextPart(trailing)
    }
}

private struct UTF8ChunkDecoder {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    mutating func decodeAvailable(allowPartial: Bool) -> String {
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

        return chunk
    }
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
