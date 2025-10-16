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

        guard let string = String(data: data, encoding: .utf8) else {
            throw ResponseStreamConversionError.invalidUTF8
        }

        return [string]

    case .stream(let stream):
        var buffer = Data()
        var decodedChunks: [String] = []

        func drainBuffer(allowPartial: Bool) throws {
            while !buffer.isEmpty {
                if let string = String(data: buffer, encoding: .utf8) {
                    decodedChunks.append(string)
                    buffer.removeAll(keepingCapacity: false)
                    continue
                }

                if !allowPartial {
                    throw ResponseStreamConversionError.invalidUTF8
                }

                var end = buffer.count - 1
                var decoded = false

                while end > 0 {
                    if let string = String(data: buffer.prefix(end), encoding: .utf8) {
                        decodedChunks.append(string)
                        buffer.removeFirst(end)
                        decoded = true
                        break
                    }
                    end -= 1
                }

                if !decoded {
                    break
                }
            }
        }

        for try await chunk in stream {
            buffer.append(chunk)
            try drainBuffer(allowPartial: true)
        }

        if !buffer.isEmpty {
            try drainBuffer(allowPartial: false)
        }

        return decodedChunks
    }
}

public enum ResponseStreamConversionError: Error, LocalizedError {
    case missingBody
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .missingBody:
            return "convertResponseStreamToArray expected a response body but found none."
        case .invalidUTF8:
            return "Response stream contained bytes that were not valid UTF-8."
        }
    }
}
