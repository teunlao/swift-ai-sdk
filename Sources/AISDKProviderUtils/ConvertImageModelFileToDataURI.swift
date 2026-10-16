import Foundation
import AISDKProvider

/**
 Convert an `ImageModelV3File` to a URL or data URI string.

 Port of `@ai-sdk/provider-utils/src/convert-image-model-file-to-data-uri.ts`.
 */
public func convertImageModelFileToDataURI(_ file: ImageModelV3File) -> String {
    switch file {
    case .url(let url, _):
        return url
    case .file(let mediaType, let data, _):
        let base64: String
        switch data {
        case .base64(let string):
            base64 = string
        case .binary(let bytes):
            base64 = bytes.base64EncodedString()
        }
        return "data:\(mediaType);base64,\(base64)"
    }
}

public func convertImageModelFileToDataURI(_ file: ImageModelV4File) -> String {
    switch file {
    case .url(let url, _): return url
    case .file(let mediaType, let data, _):
        let base64: String
        switch data {
        case .base64(let value): base64 = value
        case .binary(let value): base64 = value.base64EncodedString()
        }
        return "data:\(mediaType);base64,\(base64)"
    }
}

