import Foundation

/**
 Extracts a 1-based inclusive line range from text, preserving the detected line ending.

 Swift port of `@ai-sdk/provider-utils/src/extract-lines.ts`.
 */
public func extractLines(
    text: String,
    startLine: Int? = nil,
    endLine: Int? = nil
) -> String {
    guard startLine != nil || endLine != nil else {
        return text
    }

    let lineEnding: String
    if text.contains("\r\n") {
        lineEnding = "\r\n"
    } else if text.contains("\n") {
        lineEnding = "\n"
    } else if text.contains("\r") {
        lineEnding = "\r"
    } else {
        lineEnding = "\n"
    }

    let lines = text.components(separatedBy: lineEnding)
    let start = max(1, startLine ?? 1) - 1
    let end = max(0, min(lines.count, endLine ?? lines.count))

    guard start < lines.count, start < end else {
        return ""
    }

    return lines[start..<end].joined(separator: lineEnding)
}
