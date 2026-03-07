import Foundation
import UniformTypeIdentifiers

/**
 Converts file URLs into `FileUIPart` values.

 Port of `@ai-sdk/ai/src/ui/convert-file-list-to-file-ui-parts.ts`.

 **Adaptations**:
 - Upstream accepts browser `FileList | undefined`; Swift accepts `[URL]?` because browser
   `FileList` / `FileReader` APIs do not exist in Swift environments.
 - Local file URLs are read directly and converted into base64 data URLs.
 */
public func convertFileListToFileUIParts(
    files: [URL]?
) async throws -> [FileUIPart] {
    guard let files else {
        return []
    }

    return try files.map(convertFileURLToFileUIPart)
}

private func convertFileURLToFileUIPart(_ fileURL: URL) throws -> FileUIPart {
    guard fileURL.isFileURL else {
        throw FileListConversionError(
            message: "Only file URLs are supported in the current environment"
        )
    }

    let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    let mediaType = inferMediaType(for: fileURL, data: data)
    let dataURL = "data:\(mediaType);base64,\(data.base64EncodedString())"

    return FileUIPart(
        mediaType: mediaType,
        filename: fileURL.lastPathComponent,
        url: dataURL
    )
}

private func inferMediaType(for fileURL: URL, data: Data) -> String {
    if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
       let contentType = resourceValues.contentType,
       let mediaType = contentType.preferredMIMEType {
        return mediaType
    }

    if let mediaType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType {
        return mediaType
    }

    let signatures = imageMediaTypeSignatures + audioMediaTypeSignatures + videoMediaTypeSignatures
    if let mediaType = detectMediaType(data: data, signatures: signatures) {
        return mediaType
    }

    return "application/octet-stream"
}

private struct FileListConversionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
