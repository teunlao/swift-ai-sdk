import Foundation
import CryptoKit
import AISDKProvider

internal func canonicalJSON(_ value: JSONValue) throws -> String {
    switch value {
    case .object(let object):
        let keys = object.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        return "{" + (try keys.map { key in
            try canonicalJSON(.string(key)) + ":" + canonicalJSON(object[key]!)
        }).joined(separator: ",") + "}"
    case .array(let array):
        return "[" + (try array.map(canonicalJSON)).joined(separator: ",") + "]"
    case .number(let value):
        return canonicalNumber(value)
    default:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

internal func hashCanonical(_ value: JSONValue) throws -> String {
    let digest = SHA256.hash(data: Data(try canonicalJSON(value).utf8))
    return Data(digest).base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

// Match JSON.stringify's decimal thresholds and exponent formatting.
private func canonicalNumber(_ value: Double) -> String {
    guard value.isFinite else { return "null" }
    guard value != 0 else { return "0" }
    let sign = value < 0 ? "-" : ""
    let parts = String(abs(value)).lowercased().split(separator: "e")
    let coefficient = String(parts[0])
    let exponent = parts.count == 2 ? Int(parts[1])! : 0
    var digits = coefficient.filter { $0 != "." }
    var point = (coefficient.firstIndex(of: ".").map { coefficient.distance(from: coefficient.startIndex, to: $0) } ?? coefficient.count) + exponent
    while digits.first == "0", digits.count > 1 { digits.removeFirst(); point -= 1 }
    while digits.last == "0", digits.count > 1 { digits.removeLast() }
    if point > 0, point <= 21 {
        if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) }
        let index = digits.index(digits.startIndex, offsetBy: point)
        return sign + digits[..<index] + "." + digits[index...]
    }
    if point <= 0, point > -6 { return sign + "0." + String(repeating: "0", count: -point) + digits }
    let scientificExponent = point - 1
    let tail = digits.dropFirst()
    return sign + String(digits.first!) + (tail.isEmpty ? "" : "." + tail)
        + "e" + (scientificExponent >= 0 ? "+" : "") + String(scientificExponent)
}
