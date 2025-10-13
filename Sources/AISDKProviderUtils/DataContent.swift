import Foundation

/**
 Data content utilities for handling images, files, and other binary data in prompts.

 Port of `@ai-sdk/ai/src/prompt/data-content.ts`.

 Data content can be provided as:
 - Base64-encoded string
 - Raw Data (bytes)
 - Data URL (`data:image/png;base64,...`)
 - Regular URL pointing to the resource

 ## Example
 ```swift
 // From base64 string
 let base64 = "iVBORw0KGgoAAAA..."
 let (data, mediaType) = convertToLanguageModelV3DataContent(base64)

 // From Data URL
 let dataUrl = URL(string: "data:image/png;base64,iVBORw0KGgo...")!
 let (data2, mediaType2) = convertToLanguageModelV3DataContent(dataUrl)

 // From raw Data
 let rawData = Data([0x89, 0x50, 0x4E, 0x47])
 let (data3, mediaType3) = convertToLanguageModelV3DataContent(rawData)
 ```
 */

/**
 Union type representing data content that can be passed in prompts.

 Mirrors TypeScript's `DataContent` type from `@ai-sdk/provider-utils`.
 */
public enum DataContent: Sendable {
    /// Base64-encoded string
    case string(String)
    /// Raw binary data
    case data(Data)
}

/**
 Converts data content (string, Data, or URL) to LanguageModelV3DataContent format.

 This function handles multiple input formats:
 - **Data**: passed through as-is
 - **String**: attempted to parse as URL, if Data URL extracts base64 content
 - **URL**: if Data URL, extracts and decodes base64 content

 - Parameter content: The data content or URL to convert
 - Returns: A tuple containing the processed data and optional media type
 - Throws: `InvalidDataContentError` if the Data URL format is invalid
 */
public func convertToLanguageModelV3DataContent(
    _ content: DataContentOrURL
) throws -> (data: LanguageModelV3DataContent, mediaType: String?) {
    switch content {
    case .data(let data):
        // Raw Data → pass through
        return (data: .data(data), mediaType: nil)

    case .string(let str):
        // Try to parse string as URL
        if let url = URL(string: str), url.scheme == "data" {
            return try extractDataFromDataURL(url)
        } else if let url = URL(string: str),
                  let scheme = url.scheme,
                  (scheme == "http" || scheme == "https") {
            // Regular URL with valid http/https scheme
            return (data: .url(url), mediaType: nil)
        } else {
            // Not a valid URL, treat as base64 string
            return (data: .base64(str), mediaType: nil)
        }

    case .url(let url):
        if url.scheme == "data" {
            // Data URL → extract base64 content
            return try extractDataFromDataURL(url)
        } else {
            // Regular URL → pass through
            return (data: .url(url), mediaType: nil)
        }
    }
}

/**
 Converts data content to a base64-encoded string.

 - Parameter content: The data content to convert
 - Returns: Base64-encoded string
 */
public func convertDataContentToBase64String(_ content: DataContent) -> String {
    switch content {
    case .string(let str):
        return str
    case .data(let data):
        return convertDataToBase64(data)
    }
}

/**
 Converts data content to Data (bytes).

 - Parameter content: The data content to convert
 - Returns: Data object
 - Throws: `InvalidDataContentError` if the base64 string is malformed
 */
public func convertDataContentToData(_ content: DataContent) throws -> Data {
    switch content {
    case .data(let data):
        return data
    case .string(let str):
        do {
            return try convertBase64ToData(str)
        } catch {
            throw InvalidDataContentError(
                content: str,
                cause: error,
                message: "Invalid data content. Content string is not a base64-encoded media."
            )
        }
    }
}

/**
 Converts Data to a UTF-8 string.

 - Parameter data: The data to decode
 - Returns: UTF-8 string
 - Throws: `DecodingError` if the data is not valid UTF-8
 */
public func convertDataToText(_ data: Data) throws -> String {
    guard let text = String(data: data, encoding: .utf8) else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Error decoding Data to UTF-8 text"
            )
        )
    }
    return text
}

// MARK: - Private Helpers

private func extractDataFromDataURL(_ url: URL) throws -> (data: LanguageModelV3DataContent, mediaType: String?) {
    let dataUrlString = url.absoluteString
    let (mediaType, base64Content) = splitDataUrl(dataUrlString)

    guard let mediaType = mediaType, let base64Content = base64Content else {
        throw InvalidDataContentError(
            content: dataUrlString,
            message: "Invalid data URL format in content \(dataUrlString)"
        )
    }

    return (data: .base64(base64Content), mediaType: mediaType)
}

// MARK: - Supporting Types

/// Union type for data content or URL
public enum DataContentOrURL: Sendable, Equatable {
    case data(Data)
    case string(String)
    case url(URL)
}

// Note: LanguageModelV3DataContent is defined in Provider/LanguageModel/V3/LanguageModelV3DataContent.swift
// (uses .data(Data), .base64(String), .url(URL) cases)
