import Foundation

/// Whether `value` starts, after leading whitespace, with `{` or `[`.
func startsWithStructuredValue(_ value: String?) -> Bool {
    guard let first = value?.unicodeScalars.first(where: { !$0.properties.isWhitespace }) else {
        return false
    }
    return first == "{" || first == "["
}

/**
 Incrementally tracks whether streamed tool-call arguments contain a complete
 structured JSON value. This is structural rather than a JSON parse: a currently
 parsable scalar can still be the prefix of a later value.

 Port of `@ai-sdk/provider-utils/src/streaming-tool-call-argument-state.ts`.
 Input is scanned by Unicode scalar, as upstream iterates code points.
 */
struct StreamingToolCallArgumentState {
    private enum Structure {
        case undetermined
        case other
        case structured(stack: [Unicode.Scalar], inString: Bool, escaped: Bool, complete: Bool)
    }

    private var structure: Structure = .undetermined

    init(_ initialValue: String = "") {
        append(initialValue)
    }

    var hasCompleteStructuredValue: Bool {
        if case .structured(_, _, _, true) = structure {
            return true
        }
        return false
    }

    mutating func append(_ delta: String) {
        for scalar in delta.unicodeScalars {
            switch structure {
            case .undetermined:
                if scalar.properties.isWhitespace {
                    continue
                }
                if scalar != "{" && scalar != "[" {
                    structure = .other
                    continue
                }
                structure = .structured(stack: [scalar], inString: false, escaped: false, complete: false)

            case .other, .structured(_, _, _, true):
                // Nothing after a non-structured start or a complete value changes the state.
                return

            case .structured(var stack, var inString, var escaped, _):
                if inString {
                    if escaped {
                        escaped = false
                    } else if scalar == "\\" {
                        escaped = true
                    } else if scalar == "\"" {
                        inString = false
                    }
                    structure = .structured(stack: stack, inString: inString, escaped: escaped, complete: false)
                    continue
                }

                if scalar == "\"" {
                    inString = true
                } else if scalar == "{" || scalar == "[" {
                    stack.append(scalar)
                } else if scalar == "}" || scalar == "]" {
                    let expectedOpening: Unicode.Scalar = scalar == "}" ? "{" : "["
                    guard stack.last == expectedOpening else {
                        structure = .other
                        return
                    }
                    stack.removeLast()
                }

                structure = .structured(stack: stack, inString: inString, escaped: escaped, complete: stack.isEmpty)
            }
        }
    }
}
