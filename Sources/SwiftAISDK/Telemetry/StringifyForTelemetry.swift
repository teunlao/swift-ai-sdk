import Foundation
import AISDKProvider

public func stringifyForTelemetry(_ prompt: LanguageModelV4Prompt) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(prompt)
    guard let result = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(prompt, EncodingError.Context(codingPath: [],
            debugDescription: "Failed to convert encoded data to UTF-8 string"))
    }
    return result
}
