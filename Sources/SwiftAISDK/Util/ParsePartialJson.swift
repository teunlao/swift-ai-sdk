/**
 Parses potentially incomplete JSON text, attempting repair if needed.

 Port of `@ai-sdk/ai/src/util/parse-partial-json.ts`.

 This function handles three scenarios:
 1. Undefined input - returns undefined with 'undefined-input' state
 2. Valid JSON - parses successfully with 'successful-parse' state
 3. Invalid/partial JSON - attempts repair using fixJson, returns 'repaired-parse' or 'failed-parse'
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// The result of parsing partial JSON
public struct ParsePartialJsonResult {
    /// The parsed value, or nil if parsing failed
    public let value: JSONValue?

    /// The state of the parsing operation
    public let state: ParseState

    /// Possible states after parsing
    public enum ParseState: String, Sendable {
        case undefinedInput = "undefined-input"
        case successfulParse = "successful-parse"
        case repairedParse = "repaired-parse"
        case failedParse = "failed-parse"
    }

    public init(value: JSONValue?, state: ParseState) {
        self.value = value
        self.state = state
    }
}

/// Parses potentially incomplete JSON text, attempting repair if needed.
///
/// This function first attempts to parse the input as-is. If that fails, it uses `fixJson`
/// to repair the JSON and tries again. If both attempts fail, it returns a failed state.
///
/// - Parameter jsonText: The JSON text to parse (may be incomplete)
/// - Returns: A result containing the parsed value and parsing state
public func parsePartialJson(_ jsonText: String?) async -> ParsePartialJsonResult {
    guard let jsonText else {
        return ParsePartialJsonResult(value: nil, state: .undefinedInput)
    }

    // First attempt: parse as-is
    let result = await safeParseJSON(ParseJSONOptions(text: jsonText))

    switch result {
    case .success(let value, _):
        return ParsePartialJsonResult(value: value, state: .successfulParse)

    case .failure:
        // Second attempt: repair and parse
        let fixedJson = fixJson(jsonText)
        let repairedResult = await safeParseJSON(ParseJSONOptions(text: fixedJson))

        switch repairedResult {
        case .success(let value, _):
            return ParsePartialJsonResult(value: value, state: .repairedParse)

        case .failure:
            // Both attempts failed
            return ParsePartialJsonResult(value: nil, state: .failedParse)
        }
    }
}
