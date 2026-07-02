/**
 Download a file from a URL using URLSession.

 Port of `@ai-sdk/ai/src/util/download/download.ts`.
 */

import Foundation
import AISDKProviderUtils

/// Downloads a file from the specified URL.
///
/// - Parameter url: The URL to download from.
/// - Parameter maxBytes: Maximum allowed download size in bytes.
/// - Parameter isAborted: Optional cancellation check.
/// - Returns: A tuple containing the downloaded data and optional media type.
/// - Throws: `DownloadError` if the download fails.
public func download(
    url: URL,
    maxBytes: Int = DEFAULT_MAX_DOWNLOAD_SIZE,
    isAborted: (@Sendable () -> Bool)? = nil
) async throws -> (data: Data, mediaType: String?) {
    try await download(
        url: url,
        fetch: nil,
        maxBytes: maxBytes,
        isAborted: isAborted
    )
}

func download(
    url: URL,
    fetch: FetchFunction?,
    maxBytes: Int = DEFAULT_MAX_DOWNLOAD_SIZE,
    isAborted: (@Sendable () -> Bool)? = nil
) async throws -> (data: Data, mediaType: String?) {
    let urlText = url.absoluteString

    do {
        let userAgent = withUserAgentSuffix(
            [:],
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )

        let blob = try await downloadBlob(
            url: url,
            headers: userAgent,
            maxBytes: maxBytes,
            isAborted: isAborted,
            fetch: fetch
        )
        return (data: blob.data, mediaType: blob.mediaType)
    } catch {
        if DownloadError.isInstance(error) {
            throw error
        }

        throw DownloadError(url: urlText, cause: error)
    }
}
