/**
 Fixes incomplete or partial JSON by adding missing closing delimiters and completing partial literals.

 Port of `@ai-sdk/ai/src/util/fix-json.ts`.

 Implemented as a scanner with additional fixing that performs a single linear time scan pass over
 the partial JSON. The states match relevant states from the JSON spec: https://www.json.org/json-en.html

 Note: Invalid JSON is not considered/covered, because it is assumed that the resulting JSON
 will be processed by a standard JSON parser that will detect any invalid JSON.
 */

/// Internal state for the JSON scanner
private enum JSONState: Equatable {
    case root
    case finish
    case insideString
    case insideStringEscape
    case insideLiteral
    case insideNumber
    case insideObjectStart
    case insideObjectKey
    case insideObjectAfterKey
    case insideObjectBeforeValue
    case insideObjectAfterValue
    case insideObjectAfterComma
    case insideArrayStart
    case insideArrayAfterValue
    case insideArrayAfterComma
}

/// Fixes incomplete or partial JSON by adding missing closing delimiters and completing partial literals.
///
/// This function performs a single linear-time scan over the input, tracking the parsing state
/// and adding necessary closing characters (quotes, braces, brackets) and completing partial literals.
///
/// - Parameter input: The potentially incomplete JSON string
/// - Returns: A fixed JSON string that should be parseable by a standard JSON parser
public func fixJson(_ input: String) -> String {
    var stack: [JSONState] = [.root]
    var lastValidIndex = -1
    var literalStart: Int?

    let chars = Array(input)

    func processValueStart(char: Character, i: Int, swapState: JSONState) {
        switch char {
        case "\"":
            lastValidIndex = i
            _ = stack.popLast()
            stack.append(swapState)
            stack.append(.insideString)

        case "f", "t", "n":
            lastValidIndex = i
            literalStart = i
            _ = stack.popLast()
            stack.append(swapState)
            stack.append(.insideLiteral)

        case "-":
            _ = stack.popLast()
            stack.append(swapState)
            stack.append(.insideNumber)

        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            lastValidIndex = i
            _ = stack.popLast()
            stack.append(swapState)
            stack.append(.insideNumber)

        case "{":
            lastValidIndex = i
            _ = stack.popLast()
            stack.append(swapState)
            stack.append(.insideObjectStart)

        case "[":
            lastValidIndex = i
            _ = stack.popLast()
            stack.append(swapState)
            stack.append(.insideArrayStart)

        default:
            break
        }
    }

    func processAfterObjectValue(char: Character, i: Int) {
        switch char {
        case ",":
            _ = stack.popLast()
            stack.append(.insideObjectAfterComma)

        case "}":
            lastValidIndex = i
            _ = stack.popLast()

        default:
            break
        }
    }

    func processAfterArrayValue(char: Character, i: Int) {
        switch char {
        case ",":
            _ = stack.popLast()
            stack.append(.insideArrayAfterComma)

        case "]":
            lastValidIndex = i
            _ = stack.popLast()

        default:
            break
        }
    }

    for i in 0..<chars.count {
        let char = chars[i]
        guard let currentState = stack.last else { break }

        switch currentState {
        case .root:
            processValueStart(char: char, i: i, swapState: .finish)

        case .insideObjectStart:
            switch char {
            case "\"":
                _ = stack.popLast()
                stack.append(.insideObjectKey)

            case "}":
                lastValidIndex = i
                _ = stack.popLast()

            default:
                break
            }

        case .insideObjectAfterComma:
            switch char {
            case "\"":
                _ = stack.popLast()
                stack.append(.insideObjectKey)

            default:
                break
            }

        case .insideObjectKey:
            switch char {
            case "\"":
                _ = stack.popLast()
                stack.append(.insideObjectAfterKey)

            default:
                break
            }

        case .insideObjectAfterKey:
            switch char {
            case ":":
                _ = stack.popLast()
                stack.append(.insideObjectBeforeValue)

            default:
                break
            }

        case .insideObjectBeforeValue:
            processValueStart(char: char, i: i, swapState: .insideObjectAfterValue)

        case .insideObjectAfterValue:
            processAfterObjectValue(char: char, i: i)

        case .insideString:
            switch char {
            case "\"":
                _ = stack.popLast()
                lastValidIndex = i

            case "\\":
                stack.append(.insideStringEscape)

            default:
                lastValidIndex = i
            }

        case .insideArrayStart:
            switch char {
            case "]":
                lastValidIndex = i
                _ = stack.popLast()

            default:
                lastValidIndex = i
                processValueStart(char: char, i: i, swapState: .insideArrayAfterValue)
            }

        case .insideArrayAfterValue:
            switch char {
            case ",":
                _ = stack.popLast()
                stack.append(.insideArrayAfterComma)

            case "]":
                lastValidIndex = i
                _ = stack.popLast()

            default:
                lastValidIndex = i
            }

        case .insideArrayAfterComma:
            processValueStart(char: char, i: i, swapState: .insideArrayAfterValue)

        case .insideStringEscape:
            _ = stack.popLast()
            lastValidIndex = i

        case .insideNumber:
            switch char {
            case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                lastValidIndex = i

            case "e", "E", "-", ".":
                break

            case ",":
                _ = stack.popLast()

                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(char: char, i: i)
                }

                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(char: char, i: i)
                }

            case "}":
                _ = stack.popLast()

                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(char: char, i: i)
                }

            case "]":
                _ = stack.popLast()

                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(char: char, i: i)
                }

            default:
                _ = stack.popLast()
            }

        case .insideLiteral:
            guard let start = literalStart else { break }
            let endIndex = min(i + 1, chars.count)
            let partialLiteral = String(chars[start..<endIndex])

            if !"false".hasPrefix(partialLiteral)
                && !"true".hasPrefix(partialLiteral)
                && !"null".hasPrefix(partialLiteral)
            {
                _ = stack.popLast()

                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(char: char, i: i)
                } else if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(char: char, i: i)
                }
            } else {
                lastValidIndex = i
            }

        case .finish:
            break
        }
    }

    var result = String(input.prefix(lastValidIndex + 1))

    // Add closing delimiters based on remaining stack states
    for i in stride(from: stack.count - 1, through: 0, by: -1) {
        let state = stack[i]

        switch state {
        case .insideString:
            result += "\""

        case .insideObjectKey,
            .insideObjectAfterKey,
            .insideObjectAfterComma,
            .insideObjectStart,
            .insideObjectBeforeValue,
            .insideObjectAfterValue:
            result += "}"

        case .insideArrayStart,
            .insideArrayAfterComma,
            .insideArrayAfterValue:
            result += "]"

        case .insideLiteral:
            guard let start = literalStart else { break }
            let partialLiteral = String(chars[start..<chars.count])

            if "true".hasPrefix(partialLiteral) {
                result += String("true".dropFirst(partialLiteral.count))
            } else if "false".hasPrefix(partialLiteral) {
                result += String("false".dropFirst(partialLiteral.count))
            } else if "null".hasPrefix(partialLiteral) {
                result += String("null".dropFirst(partialLiteral.count))
            }

        default:
            break
        }
    }

    return result
}
