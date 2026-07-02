/**
 Strips file extension segments from a filename.

 Swift port of `@ai-sdk/provider-utils/src/strip-file-extension.ts`.
 */
public func stripFileExtension(_ filename: String) -> String {
    guard let firstDotIndex = filename.firstIndex(of: ".") else {
        return filename
    }

    return String(filename[..<firstDotIndex])
}
