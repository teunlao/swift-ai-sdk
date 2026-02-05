/**
 Download a file from a URL using URLSession.

 Port of `@ai-sdk/ai/src/util/download/download.ts`.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads a file from the specified URL.
///
/// - Parameter url: The URL to download from.
/// - Returns: A tuple containing the downloaded data and optional media type.
/// - Throws: `DownloadError` if the download fails.
public func download(url: URL) async throws -> (data: Data, mediaType: String?) {
    let urlText = url.absoluteString

    do {
        // Create request with User-Agent header
        var request = URLRequest(url: url)
        let userAgent = withUserAgentSuffix(
            [:],
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )

        // Set User-Agent header from the headers dictionary
        for (headerName, headerValue) in userAgent {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }

        // Perform the download
        let (data, response): (Data, URLResponse)

        #if canImport(FoundationNetworking)
        // Linux: use async wrapper for URLSession
        data = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
        #else
        // macOS/iOS: use native async/await
        (data, response) = try await URLSession.shared.data(for: request)
        #endif

        // Check HTTP response status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError(
                url: urlText,
                cause: URLError(.badServerResponse)
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let localized = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            let statusText = localized.isEmpty ? "\(httpResponse.statusCode)" : localized.capitalized
            throw DownloadError(
                url: urlText,
                statusCode: httpResponse.statusCode,
                statusText: statusText
            )
        }

        // Extract media type from Content-Type header
        let mediaType = httpResponse.value(forHTTPHeaderField: "Content-Type")

        return (data: data, mediaType: mediaType)
    } catch {
        // Re-throw DownloadError as-is
        if DownloadError.isInstance(error) {
            throw error
        }

        // Wrap other errors in DownloadError
        throw DownloadError(url: urlText, cause: error)
    }
}
