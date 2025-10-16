import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Converts various data content inputs to `LanguageModelV3DataContent` while tracking media type.
public func convertToLanguageModelV3DataContent(
    _ content: DataContentOrURL
) throws -> (data: LanguageModelV3DataContent, mediaType: String?) {
    switch content {
    case .data(let data):
        return (data: .data(data), mediaType: nil)

    case .string(let string):
        if let url = URL(string: string), url.scheme == "data" {
            return try extractDataFromDataURL(url)
        } else if let url = URL(string: string), let scheme = url.scheme,
                  scheme == "http" || scheme == "https" {
            return (data: .url(url), mediaType: nil)
        } else {
            return (data: .base64(string), mediaType: nil)
        }

    case .url(let url):
        if url.scheme == "data" {
            return try extractDataFromDataURL(url)
        } else {
            return (data: .url(url), mediaType: nil)
        }
    }
}

/// Converts `DataContent` to a base64-encoded string.
public func convertDataContentToBase64String(_ content: DataContent) -> String {
    switch content {
    case .string(let string):
        return string
    case .data(let data):
        return convertDataToBase64(data)
    }
}

/// Converts `DataContent` to raw `Data`.
public func convertDataContentToData(_ content: DataContent) throws -> Data {
    switch content {
    case .data(let data):
        return data
    case .string(let string):
        do {
            return try convertBase64ToData(string)
        } catch {
            throw InvalidDataContentError(
                content: string,
                message: "Invalid data content. Content string is not a base64-encoded media.",
                cause: error
            )
        }
    }
}

/// Converts `Data` to a UTF-8 string.
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

private func extractDataFromDataURL(_ url: URL) throws -> (data: LanguageModelV3DataContent, mediaType: String?) {
    let dataUrlString = url.absoluteString
    let (mediaType, base64Content) = splitDataUrl(dataUrlString)

    guard let mediaType, let base64Content else {
        throw InvalidDataContentError(
            content: dataUrlString,
            message: "Invalid data URL format in content \(dataUrlString)"
        )
    }

    return (data: .base64(base64Content), mediaType: mediaType)
}

private func convertBase64ToData(_ base64: String) throws -> Data {
    guard let data = Data(base64Encoded: base64) else {
        throw InvalidDataContentError(content: base64)
    }
    return data
}

private func convertDataToBase64(_ data: Data) -> String {
    data.base64EncodedString()
}

/// Splits a data URL into media type and base64 content.