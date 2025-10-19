import Foundation
import AISDKProvider

public func jsonValueToFoundation(_ value: JSONValue) -> Any {
    switch value {
    case .null:
        return NSNull()
    case .bool(let bool):
        return bool
    case .number(let number):
        return number
    case .string(let string):
        return string
    case .array(let array):
        return array.map { jsonValueToFoundation($0) }
    case .object(let object):
        return Dictionary(uniqueKeysWithValues: object.map { key, value in
            (key, jsonValueToFoundation(value))
        })
    }
}
