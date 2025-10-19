import Foundation
import AISDKProvider

enum JSONValueCompatError: Error { case unsupported }

// Minimal local converter to avoid depending on AISDKProviderUtils.
func jsonValue(from any: Any) throws -> JSONValue {
    switch any {
    case let v as JSONValue:
        return v
    case is NSNull:
        return .null
    case let b as Bool:
        return .bool(b)
    case let n as NSNumber:
        // NSNumber can be bool too; above case matches Bool explicitly.
        return .number(n.doubleValue)
    case let s as String:
        return .string(s)
    case let arr as [Any]:
        return .array(try arr.map { try jsonValue(from: $0) })
    case let dict as [String: Any]:
        var obj: [String: JSONValue] = [:]
        for (k, v) in dict { obj[k] = try jsonValue(from: v) }
        return .object(obj)
    default:
        throw JSONValueCompatError.unsupported
    }
}

