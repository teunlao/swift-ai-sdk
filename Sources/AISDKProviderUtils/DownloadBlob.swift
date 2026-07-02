import Foundation

/// Downloaded binary content plus its optional media type.
public struct DownloadedBlob: Sendable, Equatable {
    public let data: Data
    public let mediaType: String?

    public init(data: Data, mediaType: String?) {
        self.data = data
        self.mediaType = mediaType
    }
}

/// Downloads a file from a URL and returns its bytes.
public func downloadBlob(
    url: String,
    headers: [String: String]? = nil,
    maxBytes: Int = DEFAULT_MAX_DOWNLOAD_SIZE,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> DownloadedBlob {
    do {
        if url.hasPrefix("data:") {
            return try decodeDataURLBlob(url, maxBytes: maxBytes)
        }

        let response = try await fetchWithValidatedRedirects(
            url: url,
            headers: headers,
            isAborted: isAborted,
            fetch: fetch
        )

        guard (200...299).contains(response.statusCode) else {
            await cancelResponseBody(response)
            throw DownloadError(
                url: url,
                statusCode: response.statusCode,
                statusText: response.statusText
            )
        }

        let data = try await readResponseWithSizeLimit(
            response: response,
            url: url,
            maxBytes: maxBytes
        )

        return DownloadedBlob(
            data: data,
            mediaType: response.httpResponse.value(forHTTPHeaderField: "Content-Type")
        )
    } catch {
        if DownloadError.isInstance(error) {
            throw error
        }

        throw DownloadError(url: url, cause: error)
    }
}

public func downloadBlob(
    url: URL,
    headers: [String: String]? = nil,
    maxBytes: Int = DEFAULT_MAX_DOWNLOAD_SIZE,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> DownloadedBlob {
    try await downloadBlob(
        url: url.absoluteString,
        headers: headers,
        maxBytes: maxBytes,
        isAborted: isAborted,
        fetch: fetch
    )
}

private func decodeDataURLBlob(_ url: String, maxBytes: Int) throws -> DownloadedBlob {
    try validateDownloadUrl(url)

    guard let commaIndex = url.firstIndex(of: ",") else {
        throw DownloadError(url: url, message: "Invalid URL: \(url)")
    }

    let metadata = url[url.index(url.startIndex, offsetBy: 5)..<commaIndex]
    let payload = String(url[url.index(after: commaIndex)...])
    let metadataParts = metadata.split(separator: ";")
    let mediaType = metadataParts.first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
    let isBase64 = metadataParts.dropFirst().contains { $0.lowercased() == "base64" }

    let data: Data?
    if isBase64 {
        data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
    } else {
        data = payload.removingPercentEncoding?.data(using: .utf8)
    }

    guard let data else {
        throw DownloadError(url: url, message: "Invalid URL: \(url)")
    }

    if data.count > maxBytes {
        throw DownloadError(
            url: url,
            message: "Download of \(url) exceeded maximum size of \(maxBytes) bytes."
        )
    }

    return DownloadedBlob(data: data, mediaType: mediaType)
}
