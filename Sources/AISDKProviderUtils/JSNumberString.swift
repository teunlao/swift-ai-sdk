import Foundation

public func jsNumberString(_ number: Double) -> String {
    if number.isNaN { return "NaN" }
    if number == .infinity { return "Infinity" }
    if number == -.infinity { return "-Infinity" }
    if number == 0 { return "0" }
    let sign = number < 0 ? "-" : ""
    let parts = String(abs(number)).lowercased().split(separator: "e")
    var mantissa = String(parts[0])
    if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
    guard parts.count == 2, let exponent = Int(parts[1]) else { return sign + mantissa }
    if abs(number) >= 1e21 || abs(number) < 1e-6 {
        return sign + mantissa + "e" + (exponent >= 0 ? "+" : "") + String(exponent)
    }
    let point = (mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) } ?? mantissa.count) + exponent
    let digits = mantissa.replacingOccurrences(of: ".", with: "")
    if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
    if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) }
    let index = digits.index(digits.startIndex, offsetBy: point)
    return sign + String(digits[..<index]) + "." + String(digits[index...])
}
