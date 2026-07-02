import AISDKProvider
import Foundation

func generatedFileFromV4Data(mediaType: String, data: LanguageModelV4FileData) -> GeneratedFile {
    switch data {
    case .data(let data):
        return DefaultGeneratedFileWithType(data: data, mediaType: mediaType)
    case .base64(let base64):
        return DefaultGeneratedFileWithType(base64: base64, mediaType: mediaType)
    case .url(let url):
        return DefaultGeneratedFileWithType(base64: url.absoluteString, mediaType: mediaType)
    }
}
