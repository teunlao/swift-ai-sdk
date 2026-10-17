import Foundation
import AISDKProvider

func openAIJSONStringify(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    var output = ""
    func append(_ value: JSONValue) throws {
        switch value {
        case .null: output += "null"
        case .bool(let value): output += value ? "true" : "false"
        case .number(let value): output += value.isFinite ? jsNumberString(value) : "null"
        case .string(let value): output += String(decoding: try encoder.encode(value), as: UTF8.self)
        case .array(let values):
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                try append(value)
            }
            output += "]"
        case .object(let values):
            output += "{"
            // Swift dictionaries lack insertion order; sorting keeps cache prefixes stable.
            for (index, key) in values.keys.sorted().enumerated() {
                if index > 0 { output += "," }
                try append(.string(key))
                output += ":"
                try append(values[key]!)
            }
            output += "}"
        }
    }
    try append(value)
    return output
}
