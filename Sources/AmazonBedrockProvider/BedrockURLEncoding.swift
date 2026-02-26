import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Mirrors `encodeURIComponent` usage in packages/amazon-bedrock/src/*
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Percent-encodes a string using the same character set as JavaScript
/// `encodeURIComponent(...)`.
func bedrockEncodeURIComponent(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

