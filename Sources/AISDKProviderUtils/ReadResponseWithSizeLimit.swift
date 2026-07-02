import Foundation

/// Default maximum download size: 2 GiB.
public let DEFAULT_MAX_DOWNLOAD_SIZE = 2 * 1024 * 1024 * 1024

/// Reads a provider HTTP response body with a size limit.
public func readResponseWithSizeLimit(
    response: ProviderHTTPResponse,
    url: String,
    maxBytes: Int = DEFAULT_MAX_DOWNLOAD_SIZE
) async throws -> Data {
    if let contentLengthValue = response.httpResponse.value(forHTTPHeaderField: "Content-Length"),
       let contentLength = Int(contentLengthValue),
       contentLength > maxBytes {
        await cancelResponseBody(response)
        throw DownloadError(
            url: url,
            message: "Download of \(url) exceeded maximum size of \(maxBytes) bytes (Content-Length: \(contentLength))."
        )
    }

    var result = Data()

    for try await chunk in response.body.makeStream() {
        result.append(chunk)
        if result.count > maxBytes {
            await cancelResponseBody(response)
            throw DownloadError(
                url: url,
                message: "Download of \(url) exceeded maximum size of \(maxBytes) bytes."
            )
        }
    }

    return result
}
