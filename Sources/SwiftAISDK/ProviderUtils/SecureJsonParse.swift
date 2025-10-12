// Licensed under BSD-3-Clause (this file only)
// Code adapted from https://github.com/fastify/secure-json-parse/blob/783fcb1b5434709466759847cec974381939673a/index.js
//
// Copyright (c) Vercel, Inc. (https://vercel.com)
// Copyright (c) 2019 The Fastify Team
// Copyright (c) 2019, Sideway Inc, and project contributors
// All rights reserved.
//
// The complete list of contributors can be found at:
// - https://github.com/hapijs/bourne/graphs/contributors
// - https://github.com/fastify/secure-json-parse/graphs/contributors
// - https://github.com/vercel/ai/commits/main/packages/provider-utils/src/secure-parse-json.ts
//
// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation

/// Error thrown when secure JSON parsing detects forbidden prototype properties.
public struct SecureJsonParseError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

// Regular expressions to detect suspicious property names
private let suspectProtoRx = try! NSRegularExpression(pattern: #""__proto__"\s*:"#)
private let suspectConstructorRx = try! NSRegularExpression(pattern: #""constructor"\s*:"#)

/// Securely parses a JSON string, protecting against prototype pollution attacks.
///
/// This function performs two layers of protection:
/// 1. Quick regex check for suspicious property names ("__proto__", "constructor")
/// 2. Deep scan of parsed object to detect and reject forbidden properties
///
/// While Swift doesn't have JavaScript's prototype pollution vulnerability,
/// this function maintains parity with the upstream TypeScript implementation
/// and provides defense-in-depth against malicious JSON payloads.
///
/// - Parameter text: The JSON string to parse
/// - Returns: The parsed JSON value (JSONValue compatible)
/// - Throws: `SecureJsonParseError` if forbidden properties are detected,
///           or standard JSON parsing errors from Foundation
///
/// Upstream reference: packages/provider-utils/src/secure-json-parse.ts
public func secureJsonParse(_ text: String) throws -> Any {
    // Parse normally using Foundation's JSONSerialization
    guard let data = text.data(using: .utf8) else {
        throw SecureJsonParseError(message: "Invalid UTF-8 string")
    }

    let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

    // Ignore null and non-objects
    guard let dictionary = obj as? [String: Any] else {
        // Return primitives, arrays, and null as-is
        return obj
    }

    // Quick check: if text doesn't contain suspicious patterns, return early
    let range = NSRange(location: 0, length: text.utf16.count)
    let hasProto = suspectProtoRx.firstMatch(in: text, options: [], range: range) != nil
    let hasConstructor = suspectConstructorRx.firstMatch(in: text, options: [], range: range) != nil

    if !hasProto && !hasConstructor {
        return obj
    }

    // Scan result for proto keys
    try filter(obj: dictionary)
    return obj
}

/// Recursively filters an object for forbidden prototype properties.
/// Uses breadth-first search to scan all nested objects.
///
/// - Parameter obj: The object to scan (must be a dictionary)
/// - Throws: `SecureJsonParseError` if forbidden properties are found
private func filter(obj: [String: Any]) throws {
    var next: [[String: Any]] = [obj]

    while !next.isEmpty {
        let nodes = next
        next = []

        for node in nodes {
            // Check for forbidden "__proto__" property
            if node.keys.contains("__proto__") {
                throw SecureJsonParseError(message: "Object contains forbidden prototype property")
            }

            // Check for "constructor" with "prototype" property
            if node.keys.contains("constructor"),
               let constructor = node["constructor"] as? [String: Any],
               constructor.keys.contains("prototype") {
                throw SecureJsonParseError(message: "Object contains forbidden prototype property")
            }

            // Add nested dictionaries to next scan level
            for (_, value) in node {
                // Recursively collect all dictionaries from any nested structure
                next.append(contentsOf: collectDictionaries(from: value))
            }
        }
    }
}

/// Recursively collects all dictionaries from a value, including deeply nested arrays.
///
/// This ensures parity with upstream TypeScript behavior where any object
/// (including arrays) is traversed to find nested dictionaries at any depth.
///
/// - Parameter value: The value to scan (can be dictionary, array, or primitive)
/// - Returns: Array of all dictionaries found in the value tree
private func collectDictionaries(from value: Any) -> [[String: Any]] {
    if let dict = value as? [String: Any] {
        // Direct dictionary - return it
        return [dict]
    } else if let array = value as? [Any] {
        // Array - recursively collect dictionaries from all elements
        return array.flatMap { collectDictionaries(from: $0) }
    } else {
        // Primitive value - no dictionaries
        return []
    }
}
