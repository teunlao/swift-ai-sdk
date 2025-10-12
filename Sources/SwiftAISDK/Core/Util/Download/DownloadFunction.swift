/**
 Download function type for handling URL downloads.

 Port of `@ai-sdk/ai/src/util/download/download-function.ts`.

 Experimental. Can change in patch versions without warning.
 */

import Foundation

/// Represents a download request for a single URL.
public struct DownloadRequest: Sendable {
    /// The URL to download.
    public let url: URL

    /// Whether the URL is supported natively by the model.
    /// If true, the download function may return nil to pass through the URL.
    public let isUrlSupportedByModel: Bool

    public init(url: URL, isUrlSupportedByModel: Bool) {
        self.url = url
        self.isUrlSupportedByModel = isUrlSupportedByModel
    }
}

/// Represents the result of a download operation.
public struct DownloadResult: Sendable {
    /// The downloaded data.
    public let data: Data

    /// The media type of the downloaded asset, if known.
    public let mediaType: String?

    public init(data: Data, mediaType: String?) {
        self.data = data
        self.mediaType = mediaType
    }
}

/**
 Download function. Called with an array of URLs and a boolean indicating
 whether the URL is supported by the model.

 The download function can decide for each URL:
 - to return nil (which means that the URL should be passed to the model)
 - to download the asset and return the data (incl. retries, authentication, etc.)

 Should throw DownloadError if the download fails.

 Should return an array of results sorted by the order of the requested downloads.
 For each result, the data should contain downloaded bytes if the URL was downloaded.
 For each result, the mediaType should be the media type of the downloaded asset.
 For each result, nil means the URL should be passed through as-is to the model.

 Experimental. Can change in patch versions without warning.
 */
public typealias DownloadFunction = ([DownloadRequest]) async throws -> [DownloadResult?]

/**
 Creates a default download function.

 Downloads the file if it is not supported by the model.

 - Parameter downloadImpl: The download implementation to use. Defaults to the built-in `download` function.
 - Returns: A download function that processes an array of download requests.
 */
public func createDefaultDownloadFunction(
    downloadImpl: @escaping @Sendable (URL) async throws -> (data: Data, mediaType: String?) = download
) -> DownloadFunction {
    return { requestedDownloads in
        // Process all downloads concurrently using TaskGroup
        return try await withThrowingTaskGroup(of: (Int, DownloadResult?).self) { group in
            // Add tasks for each download request
            for (index, requestedDownload) in requestedDownloads.enumerated() {
                group.addTask {
                    // If URL is supported by model, return nil (pass-through)
                    if requestedDownload.isUrlSupportedByModel {
                        return (index, nil)
                    }

                    // Otherwise, download the file
                    let result = try await downloadImpl(requestedDownload.url)
                    return (
                        index,
                        DownloadResult(data: result.data, mediaType: result.mediaType)
                    )
                }
            }

            // Collect results in order
            var results: [(Int, DownloadResult?)] = []
            for try await result in group {
                results.append(result)
            }

            // Sort by index to maintain request order
            results.sort { $0.0 < $1.0 }
            return results.map { $0.1 }
        }
    }
}
