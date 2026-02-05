import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Generate image prompt.

 Port of `GenerateImagePrompt` from `@ai-sdk/ai/src/generate-image/generate-image.ts`.
 */
public enum GenerateImagePrompt: Sendable {
    case text(String)
    case imageEditing(text: String?, images: [DataContent], mask: DataContent?)
}

extension GenerateImagePrompt {
    public static func imageEditing(
        images: [DataContent],
        text: String? = nil,
        mask: DataContent? = nil
    ) -> GenerateImagePrompt {
        .imageEditing(text: text, images: images, mask: mask)
    }

    func normalize() throws -> (prompt: String?, files: [ImageModelV3File]?, mask: ImageModelV3File?) {
        switch self {
        case .text(let text):
            return (prompt: text, files: nil, mask: nil)

        case .imageEditing(let text, let images, let mask):
            let files = try images.map { try toImageModelV3File($0) }
            let maskFile = try mask.map { try toImageModelV3File($0) }
            return (prompt: text, files: files, mask: maskFile)
        }
    }
}

private func toImageModelV3File(_ dataContent: DataContent) throws -> ImageModelV3File {
    switch dataContent {
    case .string(let string):
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return .url(url: string, providerOptions: nil)
        }

        if string.hasPrefix("data:") {
            let (dataUrlMediaType, base64Content) = splitDataUrl(string)

            if let base64Content {
                let data = try convertBase64ToData(base64Content)
                let mediaType = dataUrlMediaType
                    ?? detectMediaType(data: data, signatures: imageMediaTypeSignatures)
                    ?? "image/png"
                return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)
            }
        }

        let data = try convertBase64ToData(string)
        let mediaType = detectMediaType(data: data, signatures: imageMediaTypeSignatures) ?? "image/png"
        return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)

    case .data(let data):
        let mediaType = detectMediaType(data: data, signatures: imageMediaTypeSignatures) ?? "image/png"
        return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)
    }
}
