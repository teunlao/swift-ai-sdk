import Foundation
import AISDKProvider

/**
 Converts inline file data into raw bytes.

 Swift port of
 `@ai-sdk/provider-utils/src/convert-inline-file-data-to-uint8-array.ts`.
 */
public func convertInlineFileDataToData(_ data: SharedV4DataContent) throws -> Data {
    switch data {
    case .text(let text):
        return Data(text.utf8)
    case .data(let data):
        return data
    case .base64(let base64):
        return try convertBase64ToData(base64)
    }
}
