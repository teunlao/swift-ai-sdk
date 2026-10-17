import Foundation
import AISDKProviderUtils

struct DeepgramConfig: Sendable {
    let provider: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

struct QueryParameters {
    private var keys: [String] = []
    private var values: [String: String] = [:]
    subscript(key: String) -> String? {
        get { values[key] }
        set {
            if newValue == nil { keys.removeAll { $0 == key } }
            else if values[key] == nil { keys.append(key) }
            values[key] = newValue
        }
    }
    func url(_ base: String) -> String {
        func encode(_ string: String) -> String {
            string.utf8.map { byte in
                switch byte {
                case 65...90, 97...122, 48...57, 42, 45, 46, 95: String(UnicodeScalar(byte))
                case 32: "+"
                default: String(format: "%%%02X", byte)
                }
            }.joined()
        }
        return base + "?" + keys.compactMap { key in values[key].map { encode(key) + "=" + encode($0) } }.joined(separator: "&")
    }
}

let ecmaWhitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

func numberFromString(_ string: String) -> Double {
    let value = string.trimmingCharacters(in: ecmaWhitespace)
    if value.isEmpty { return 0 }
    if value == "Infinity" || value == "+Infinity" { return .infinity }
    if value == "-Infinity" { return -.infinity }
    for (prefix, radix) in [("0x", 16), ("0b", 2), ("0o", 8)] where value.lowercased().hasPrefix(prefix) {
        let digits = value.dropFirst(2)
        guard !digits.isEmpty else { return .nan }
        var number: Double = 0
        for digit in digits {
            guard digit.isASCII, let integer = digit.hexDigitValue, integer < radix else { return .nan }
            number = number * Double(radix) + Double(integer)
        }
        return number
    }
    guard value.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$", options: .regularExpression) != nil else { return .nan }
    return Double(value) ?? .nan
}

func numberString(_ value: Double) -> String {
    if value == 0 { return "0" }
    if value.isNaN { return "NaN" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    let encoded = String(value).lowercased()
    let sign = encoded.hasPrefix("-") ? "-" : ""
    let magnitude = sign.isEmpty ? encoded[...] : encoded.dropFirst()
    let parts = magnitude.split(separator: "e", maxSplits: 1)
    let exponent = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
    let integerDigits = parts[0].prefix { $0 != "." }.count
    let rawDigits = parts[0].filter { $0 != "." }
    let zeros = rawDigits.prefix { $0 == "0" }.count
    var digits = rawDigits.dropFirst(zeros)
    while digits.last == "0" { digits = digits.dropLast() }
    let position = integerDigits + exponent - zeros
    let power = position - 1
    if power >= -6 && power < 21 {
        if position <= 0 { return sign + "0." + String(repeating: "0", count: -position) + digits }
        if position >= digits.count { return sign + digits + String(repeating: "0", count: position - digits.count) }
        let point = digits.index(digits.startIndex, offsetBy: position)
        return sign + digits[..<point] + "." + digits[point...]
    }
    let tail = digits.dropFirst()
    let coefficient = String(digits.prefix(1)) + (tail.isEmpty ? "" : "." + tail)
    return sign + coefficient + "e" + (power >= 0 ? "+" : "") + String(power)
}
