/**
 Returns the index of the start of the searched text in the text, or nil if it is not found.

 Port of `@ai-sdk/ai/src/util/get-potential-start-index.ts`.

 This function performs two types of searches:
 1. Direct substring match (returns the index if found)
 2. Suffix-prefix match (finds the largest suffix of text that matches a prefix of searchedText)

 The suffix-prefix matching is useful for detecting partial matches at the end of a stream,
 where the searchedText might be split across chunks.
 */

/// Returns the index of the start of the searched text in the text, or `nil` if it is not found.
///
/// This function first attempts to find the `searchedText` as a direct substring.
/// If not found, it looks for the largest suffix of `text` that matches a prefix of `searchedText`.
///
/// - Parameters:
///   - text: The text to search within
///   - searchedText: The text to search for
/// - Returns: The starting index of the match, or `nil` if no match is found
public func getPotentialStartIndex(text: String, searchedText: String) -> Int? {
    // Return nil immediately if searchedText is empty
    guard !searchedText.isEmpty else {
        return nil
    }

    // Check if the searchedText exists as a direct substring of text
    if let directRange = text.range(of: searchedText) {
        return text.distance(from: text.startIndex, to: directRange.lowerBound)
    }

    // Otherwise, look for the largest suffix of "text" that matches
    // a prefix of "searchedText". We go from the end of text inward.
    for i in stride(from: text.count - 1, through: 0, by: -1) {
        let suffixStartIndex = text.index(text.startIndex, offsetBy: i)
        let suffix = String(text[suffixStartIndex...])

        if searchedText.hasPrefix(suffix) {
            return i
        }
    }

    return nil
}
