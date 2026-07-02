import AISDKProvider

/**
 Resolves a file part's media type to full `type/subtype` form.

 Swift port of `@ai-sdk/provider-utils/src/resolve-full-media-type.ts`.
 */
public func resolveFullMediaType(part: LanguageModelV4FilePart) throws -> String {
    if isFullMediaType(part.mediaType) {
        return part.mediaType
    }

    let topLevelType = getTopLevelMediaType(part.mediaType)

    switch part.data {
    case .data(let data):
        if let detected = detectMediaType(data: data, topLevelType: topLevelType) {
            return detected
        }

        throw UnsupportedFunctionalityError(
            functionality: #"file of media type "\#(part.mediaType)" must specify subtype since it could not be auto-detected"#
        )

    case .base64(let base64):
        if let detected = detectMediaType(data: base64, topLevelType: topLevelType) {
            return detected
        }

        throw UnsupportedFunctionalityError(
            functionality: #"file of media type "\#(part.mediaType)" must specify subtype since it could not be auto-detected"#
        )

    case .url, .reference, .text:
        throw UnsupportedFunctionalityError(
            functionality: #"file of media type "\#(part.mediaType)" must specify subtype since it is not passed as inline bytes"#
        )
    }
}
