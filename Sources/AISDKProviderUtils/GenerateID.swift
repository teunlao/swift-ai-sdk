import Foundation
import AISDKProvider

/**
 A function that generates an ID.

 Port of `@ai-sdk/provider-utils/src/generate-id.ts`
 */
public typealias IDGenerator = @Sendable () -> String

/**
 Creates an ID generator.
 The total length of the ID is the sum of the prefix, separator, and random part length.
 Not cryptographically secure.

 - Parameters:
   - alphabet: The alphabet to use for the ID. Default: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.
   - prefix: The prefix of the ID to generate. Optional.
   - separator: The separator between the prefix and the random part of the ID. Default: '-'.
   - size: The size of the random part of the ID to generate. Default: 16.

 - Throws: `InvalidArgumentError` if the separator is part of the alphabet.

 - Returns: An `IDGenerator` function that generates IDs.
 */
public func createIDGenerator(
    prefix: String? = nil,
    separator: String = "-",
    size: Int = 16,
    alphabet: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
) throws -> IDGenerator {
    let alphabetArray = Array(alphabet)
    let alphabetLength = alphabetArray.count

    let generator: @Sendable () -> String = {
        var chars = [Character]()
        chars.reserveCapacity(size)

        for _ in 0..<size {
            let randomIndex = Int.random(in: 0..<alphabetLength)
            chars.append(alphabetArray[randomIndex])
        }

        return String(chars)
    }

    guard let prefix = prefix else {
        return generator
    }

    // Check that the separator is not part of the alphabet (otherwise prefix checking can fail randomly)
    if alphabet.contains(separator) {
        throw InvalidArgumentError(
            argument: "separator",
            message: "The separator \"\(separator)\" must not be part of the alphabet \"\(alphabet)\"."
        )
    }

    return {
        "\(prefix)\(separator)\(generator())"
    }
}

/**
 Generates a 16-character random string to use for IDs.
 Not cryptographically secure.

 Port of `@ai-sdk/provider-utils/src/generate-id.ts::generateId`
 */
public let generateID: IDGenerator = {
    // Using try! is safe here because we use default parameters that are validated
    try! createIDGenerator()
}()
