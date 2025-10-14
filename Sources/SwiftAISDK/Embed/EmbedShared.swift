import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Shared helpers for the Embed API.

 Port of common utilities from `@ai-sdk/ai/src/embed/embed.ts` and
 `@ai-sdk/ai/src/embed/embed-many.ts`.
 */

// MARK: - Telemetry Helpers

/// Builds telemetry attribute descriptors by combining standard operation metadata with additional entries.
func makeEmbedTelemetryAttributes(
    operationId: String,
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    additional: [String: ResolvableAttributeValue?] = [:]
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: operationId, telemetry: telemetry) {
        attributes[key] = .value(value)
    }

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    for (key, value) in additional {
        attributes[key] = value
    }

    return attributes
}

/// Converts a value into a JSON-like string representation for telemetry attributes.
///
/// Mirrors the behaviour of `JSON.stringify` used in upstream telemetry.
/// Falls back to `String(describing:)` when JSON representation is not available.
func embedTelemetryJSONString(from rawValue: Any?) -> String {
    guard let value = unwrapOptional(rawValue) else {
        return "null"
    }

    if let jsonValue = value as? JSONValue, let json = embedJSONString(from: jsonValue) {
        return json
    }

    if let string = value as? String {
        return "\"\(escapeJSONString(string))\""
    }

    if let bool = value as? Bool {
        return bool ? "true" : "false"
    }

    if let double = value as? Double {
        return double.isFinite ? normalizeNumberString(double) : "null"
    }

    if let float = value as? Float {
        return float.isFinite ? normalizeNumberString(Double(float)) : "null"
    }

    if let int = value as? Int {
        return String(int)
    }

    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        return normalizeNumberString(number.doubleValue)
    }

    if let data = value as? Data {
        return "\"\(data.base64EncodedString())\""
    }

    if let array = value as? NSArray {
        let stringified = array.map { element in
            embedTelemetryJSONString(from: element)
        }
        return "[\(stringified.joined(separator: ","))]"
    }

    if let dictionary = value as? NSDictionary {
        var pairs: [String] = []
        for case let (key as String, value) in dictionary {
            let valueString = embedTelemetryJSONString(from: value)
            pairs.append("\"\(escapeJSONString(key))\":\(valueString)")
        }
        return "{\(pairs.joined(separator: ","))}"
    }

    if let describable = value as? CustomStringConvertible {
        return "\"\(escapeJSONString(describable.description))\""
    }

    return "\"\(escapeJSONString(String(describing: value)))\""
}

/// Produces an attribute-ready array of telemetry strings.
func embedTelemetryJSONStringArray(from values: [Any]) -> [String] {
    values.map { embedTelemetryJSONString(from: $0) }
}

/// Escapes a string for JSON output.
private func escapeJSONString(_ string: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(string.count)

    for scalar in string.unicodeScalars {
        switch scalar.value {
        case 0x22: // "
            escaped.append("\\\"")
        case 0x5C: // \
            escaped.append("\\\\")
        case 0x08:
            escaped.append("\\b")
        case 0x0C:
            escaped.append("\\f")
        case 0x0A:
            escaped.append("\\n")
        case 0x0D:
            escaped.append("\\r")
        case 0x09:
            escaped.append("\\t")
        case 0x00..<0x20:
            let hex = String(format: "\\u%04X", scalar.value)
            escaped.append(hex)
        default:
            escaped.append(String(scalar))
        }
    }

    return escaped
}

/// Normalizes number printing to avoid exponential representation for common values.
private func normalizeNumberString(_ number: Double) -> String {
    if number.isFinite {
        if number == floor(number) {
            return String(Int(number))
        }
        let string = String(number)
        if string.contains(".") {
            var trimmed = string
            while trimmed.last == "0" {
                trimmed.removeLast()
            }
            if trimmed.last == "." {
                trimmed.removeLast()
            }
            if trimmed.isEmpty {
                return "0"
            }
            return trimmed
        }
        return string
    }
    return "null"
}

/// Unwraps optional values recursively.
private func unwrapOptional(_ value: Any?) -> Any? {
    guard let value else {
        return nil
    }

    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle != .optional {
        return value
    }

    if let child = mirror.children.first {
        return unwrapOptional(child.value)
    }

    return nil
}

/// Serializes a JSONValue into a deterministic JSON string.
private func embedJSONString(from value: JSONValue) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

// MARK: - Usage Helpers

/// Converts provider usage information into public `EmbeddingModelUsage`.
///
/// Upstream uses `NaN` when usage is unavailable. Since Swift integers cannot represent
/// `NaN`, we default to `0` in that case. This matches the ergonomic behaviour of treating
/// missing usage as "unknown/zero" while keeping the API non-optional.
func makeEmbeddingUsage(from usage: EmbeddingModelV3Usage?) -> EmbeddingModelUsage {
    EmbeddingModelUsage(tokens: usage?.tokens ?? 0)
}

// MARK: - Provider Metadata Merge

/// Merges provider metadata dictionaries in-place.
func mergeProviderMetadata(
    target: inout ProviderMetadata?,
    source: ProviderMetadata?
) {
    guard let source else {
        return
    }

    if target == nil {
        target = source
        return
    }

    for (provider, metadata) in source {
        var merged = target?[provider] ?? [:]
        for (key, value) in metadata {
            merged[key] = value
        }
        target?[provider] = merged
    }
}
