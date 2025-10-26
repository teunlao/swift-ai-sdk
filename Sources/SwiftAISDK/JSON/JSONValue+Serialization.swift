import Foundation
import AISDKProvider

enum JSONValueEncoding {
    static func jsonValue<T: Encodable>(from value: T) -> JSONValue? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let jsonValue = JSONValue(jsonObject: jsonObject) else {
            return nil
        }
        return jsonValue
    }

    static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

extension JSONValue {
    init?(jsonObject any: Any) {
        switch any {
        case let dictionary as [String: Any]:
            var map: [String: JSONValue] = [:]
            for (key, value) in dictionary {
                guard let jsonValue = JSONValue(jsonObject: value) else { return nil }
                map[key] = jsonValue
            }
            self = .object(map)
        case let array as [Any]:
            var values: [JSONValue] = []
            values.reserveCapacity(array.count)
            for value in array {
                guard let jsonValue = JSONValue(jsonObject: value) else { return nil }
                values.append(jsonValue)
            }
            self = .array(values)
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case _ as NSNull:
            self = .null
        default:
            return nil
        }
    }

    func toJSONObject() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map { $0.toJSONObject() }
        case .object(let map):
            return map.mapValues { $0.toJSONObject() }
        }
    }

    func toJSONData(prettyPrinted: Bool, sortedKeys: Bool) throws -> Data {
        var options: JSONSerialization.WritingOptions = []
        if prettyPrinted { options.insert(.prettyPrinted) }
        if sortedKeys { options.insert(.sortedKeys) }
        let object = toJSONObject()
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    func toJSONString(prettyPrinted: Bool, sortedKeys: Bool) throws -> String {
        let data = try toJSONData(prettyPrinted: prettyPrinted, sortedKeys: sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }
}
