import Foundation
import CoreFoundation
import AISDKProvider

public func getTextFromDataUrl(_ dataUrl: String) throws -> String {
    let segments = dataUrl.split(separator: ",", omittingEmptySubsequences: false)
    let header = String(segments[0])
    guard segments.count >= 2,
          header.split(separator: ";", omittingEmptySubsequences: false)[0].contains(":") else {
        throw InvalidArgumentError(parameter: "dataUrl", value: .string(dataUrl), message: "Invalid data URL format")
    }
    func decodingError() -> InvalidArgumentError {
        InvalidArgumentError(parameter: "dataUrl", value: .string(dataUrl), message: "Error decoding data URL")
    }
    let asciiWhitespace: Set<UnicodeScalar> = ["\t", "\n", "\u{0C}", "\r", " "]
    let encoded = String(String.UnicodeScalarView(segments[1].unicodeScalars.filter { !asciiWhitespace.contains($0) }))
    var content = encoded
    if content.utf8.count % 4 == 0 {
        if content.hasSuffix("==") { content.removeLast(2) }
        else if content.hasSuffix("=") { content.removeLast() }
    }
    let remainder = content.utf8.count % 4
    guard remainder != 1, content.utf8.allSatisfy({ byte in
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 43 || byte == 47
    }), let data = Data(base64Encoded: content + String(repeating: "=", count: remainder == 0 ? 0 : 4 - remainder)) else {
        throw decodingError()
    }
    let pattern = #"(?:^|;)\s*charset\s*=\s*(?:"([^"]+)"|([^;\s]+))"#
    let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    guard let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
        return String(String.UnicodeScalarView(data.map { UnicodeScalar($0) }))
    }
    let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
    guard let labelRange = Range(range, in: header) else { throw decodingError() }
    let label = header[labelRange].trimmingCharacters(in: CharacterSet(charactersIn: "\t\n\u{0C}\r ")).lowercased()
    if ["utf-8", "utf8", "unicode-1-1-utf-8"].contains(label) {
        return withoutByteOrderMark(String(decoding: data, as: UTF8.self))
    }
    if ["utf-16", "utf-16le"].contains(label) {
        let units = stride(from: 0, to: data.count - data.count % 2, by: 2).map { UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8 }
        return withoutByteOrderMark(String(decoding: units, as: UTF16.self) + (data.count % 2 == 0 ? "" : "\u{FFFD}"))
    }
    if label == "utf-16be" {
        let units = stride(from: 0, to: data.count - data.count % 2, by: 2).map { UInt16(data[$0]) << 8 | UInt16(data[$0 + 1]) }
        return withoutByteOrderMark(String(decoding: units, as: UTF16.self) + (data.count % 2 == 0 ? "" : "\u{FFFD}"))
    }
    let windowsLatin1 = ["ansi_x3.4-1968", "ascii", "cp1252", "cp819", "csisolatin1", "ibm819", "iso-8859-1", "iso-ir-100", "iso8859-1", "iso88591", "iso_8859-1", "iso_8859-1:1987", "l1", "latin1", "us-ascii", "windows-1252", "x-cp1252"]
    if windowsLatin1.contains(label) {
        let controls: [UInt32] = [0x20AC, 0x81, 0x201A, 0x192, 0x201E, 0x2026, 0x2020, 0x2021, 0x2C6, 0x2030, 0x160, 0x2039, 0x152, 0x8D, 0x17D, 0x8F, 0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x2DC, 0x2122, 0x161, 0x203A, 0x153, 0x9D, 0x17E, 0x178]
        return String(String.UnicodeScalarView(data.map { byte in
            UnicodeScalar((0x80...0x9F).contains(byte) ? controls[Int(byte) - 0x80] : UInt32(byte))!
        }))
    }
    if label == "latin-1" { throw decodingError() }
    let encoding = CFStringConvertIANACharSetNameToEncoding(label as CFString)
    guard encoding != kCFStringEncodingInvalidId,
          let text = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) else {
        throw decodingError()
    }
    return withoutByteOrderMark(text)
}

private func withoutByteOrderMark(_ text: String) -> String {
    text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
}
