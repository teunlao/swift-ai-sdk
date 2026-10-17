import Foundation
import AISDKProvider

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

