import Foundation
import AISDKProvider

struct GoogleModelCapabilities {
    let supportsGemini2Tools: Bool
    let supportsFileSearch: Bool
    let usesGemini3Features: Bool
}

func googleModelMatches(_ modelId: String, _ pattern: String) -> Bool {
    modelId.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}

func googleModelCapabilities(_ modelId: String) -> GoogleModelCapabilities {
    let gemini = googleModelMatches(modelId, "(^|[/.])gemini-")
    let older = googleModelMatches(modelId, "(^|[/.])gemini-1(?:[.-]|$)")
        || googleModelMatches(modelId, "(^|[/.])gemini-pro(?:-vision)?$")
        || googleModelMatches(modelId, "(^|[/.])gemini-robotics-er-1\\.5(?:[.-]|$)")
    let gemini2 = googleModelMatches(modelId, "(^|[/.])gemini-2(?:[.-]|$)")
    let newest = gemini && !older && !gemini2
    return .init(
        supportsGemini2Tools: (gemini && !older) || modelId.lowercased().contains("nano-banana"),
        supportsFileSearch: googleModelMatches(modelId, "(^|[/.])gemini-2\\.5(?:[.-]|$)") || newest,
        usesGemini3Features: newest
    )
}

func sanitizeGoogleResponseSchema(_ schema: JSONValue) -> JSONValue {
    guard case .object(var result) = schema else { return schema }
    if let constant = result.removeValue(forKey: "const") { result["enum"] = .array([constant]) }
    for key in ["properties", "$defs"] {
        if case .object(let values) = result[key] {
            result[key] = .object(values.mapValues(sanitizeGoogleResponseSchema))
        }
    }
    for key in ["items", "additionalProperties", "anyOf", "oneOf"] {
        if case .array(let values) = result[key] {
            result[key] = .array(values.map(sanitizeGoogleResponseSchema))
        } else if let value = result[key] {
            result[key] = sanitizeGoogleResponseSchema(value)
        }
    }
    return .object(result)
}

func googleProviderOptionsNames(_ provider: String) -> [String] {
    provider.contains("vertex") ? ["googleVertex", "vertex"] : ["google"]
}

func googleProviderMetadata(_ payload: [String: JSONValue], names: [String]) -> SharedV4ProviderMetadata {
    Dictionary(uniqueKeysWithValues: names.map { ($0, payload) })
}
