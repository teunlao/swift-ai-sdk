import Foundation

enum DefaultValueFactory {
    private static let stackKey = "ai.sdk.jsonschema.default-value-stack"

    static func make<T: Decodable>(_ type: T.Type) throws -> T {
        if let value: T = try makeKnown(type) {
            return value
        }

        return try withRecursionGuard(type) {
            try T(from: PlaceholderDecoder())
        }
    }

    static func makeAny(_ type: Decodable.Type) throws -> Any {
        if let known = try makeKnown(type) {
            return known
        }

        return try withRecursionGuard(type) {
            try type.init(from: PlaceholderDecoder())
        }
    }
}

private extension DefaultValueFactory {
    static func makeKnown<T: Decodable>(_ type: T.Type) throws -> T? {
        if type == String.self { return "" as? T }
        if type == Bool.self { return false as? T }
        if type == Double.self { return 0 as? T }
        if type == Float.self { return 0 as? T }
        if type == Decimal.self { return Decimal.zero as? T }
        if type == Int.self { return 0 as? T }
        if type == Int8.self { return 0 as? T }
        if type == Int16.self { return 0 as? T }
        if type == Int32.self { return 0 as? T }
        if type == Int64.self { return 0 as? T }
        if type == UInt.self { return 0 as? T }
        if type == UInt8.self { return 0 as? T }
        if type == UInt16.self { return 0 as? T }
        if type == UInt32.self { return 0 as? T }
        if type == UInt64.self { return 0 as? T }
        if type == Date.self { return Date(timeIntervalSince1970: 0) as? T }
        if type == Data.self { return Data() as? T }
        if type == URL.self { return URL(string: "https://example.com") as? T }

        if let optionalType = type as? AnyOptional.Type {
            return optionalType.makeNil() as? T
        }

        if let arrayType = type as? AnyArray.Type {
            return try arrayType.sampleArray() as? T
        }

        if let dictionaryType = type as? AnyDictionary.Type {
            return dictionaryType.emptyDictionary() as? T
        }

        if let caseIterable = type as? any CaseIterable.Type {
            let mirror = Mirror(reflecting: caseIterable.allCases)
            if let first = mirror.children.first?.value as? T {
                return first
            }
        }

        return nil
    }

    static func makeKnown(_ type: Decodable.Type) throws -> Any? {
        switch type {
        case is String.Type: return ""
        case is Bool.Type: return false
        case is Double.Type: return 0.0
        case is Float.Type: return Float.zero
        case is Decimal.Type: return Decimal.zero
        case is Int.Type: return 0
        case is Int8.Type: return Int8.zero
        case is Int16.Type: return Int16.zero
        case is Int32.Type: return Int32.zero
        case is Int64.Type: return Int64.zero
        case is UInt.Type: return UInt.zero
        case is UInt8.Type: return UInt8.zero
        case is UInt16.Type: return UInt16.zero
        case is UInt32.Type: return UInt32.zero
        case is UInt64.Type: return UInt64.zero
        case is Date.Type: return Date(timeIntervalSince1970: 0)
        case is Data.Type: return Data()
        case is URL.Type: return URL(string: "https://example.com") as Any
        default: break
        }

        if let optionalType = type as? AnyOptional.Type {
            return optionalType.makeNil()
        }

        if let arrayType = type as? AnyArray.Type {
            return try arrayType.sampleArray()
        }

        if let dictionaryType = type as? AnyDictionary.Type {
            return dictionaryType.emptyDictionary()
        }

        if let caseIterable = type as? any CaseIterable.Type {
            let mirror = Mirror(reflecting: caseIterable.allCases)
            if let first = mirror.children.first?.value {
                return first
            }
        }

        return nil
    }

    static func withRecursionGuard<T>(_ type: Any.Type, _ body: () throws -> T) throws -> T {
        let identifier = ObjectIdentifier(type as Any.Type)
        let thread = Thread.current
        var stack = thread.threadDictionary[stackKey] as? [ObjectIdentifier] ?? []

        if stack.contains(identifier) {
            throw PlaceholderError.recursiveType(String(describing: type))
        }

        stack.append(identifier)
        thread.threadDictionary[stackKey] = stack
        defer {
            if var updated = thread.threadDictionary[stackKey] as? [ObjectIdentifier],
               let last = updated.last, last == identifier {
                updated.removeLast()
                thread.threadDictionary[stackKey] = updated.isEmpty ? nil : updated
            }
        }

        return try body()
    }
}

private final class PlaceholderDecoder: Decoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init(codingPath: [CodingKey] = []) {
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        let container = PlaceholderKeyedContainer<Key>(codingPath: codingPath)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        PlaceholderUnkeyedContainer(codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        PlaceholderSingleValueContainer(codingPath: codingPath)
    }
}

private struct PlaceholderKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let codingPath: [CodingKey]
    var allKeys: [Key] { [] }

    func contains(_ key: Key) -> Bool { true }

    func decodeNil(forKey key: Key) throws -> Bool { true }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { false }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { "" }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { 0 }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { 0 }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { 0 }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { 0 }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { 0 }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { 0 }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { 0 }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { 0 }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { 0 }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { 0 }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { 0 }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { 0 }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        try DefaultValueFactory.withRecursionGuard(type) {
            if let known: T = try DefaultValueFactory.makeKnown(type) {
                return known
            }

            let decoder = PlaceholderDecoder(codingPath: codingPath + [key])
            return try T(from: decoder)
        }
    }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? { nil }
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? { nil }
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? { nil }
    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? { nil }
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? { nil }
    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? { nil }
    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? { nil }
    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? { nil }
    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? { nil }
    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? { nil }
    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? { nil }
    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? { nil }
    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? { nil }
    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? { nil }

    func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T: Decodable {
        nil
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        let decoder = PlaceholderDecoder(codingPath: codingPath + [key])
        return try decoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        PlaceholderUnkeyedContainer(codingPath: codingPath + [key])
    }

    func superDecoder() throws -> Decoder {
        PlaceholderDecoder(codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        PlaceholderDecoder(codingPath: codingPath + [key])
    }
}

private struct PlaceholderUnkeyedContainer: UnkeyedDecodingContainer {
    let codingPath: [CodingKey]
    private var remaining: Int

    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
        self.remaining = 1
    }

    var count: Int? { 1 }
    var isAtEnd: Bool { remaining == 0 }
    var currentIndex: Int { 1 - remaining }

    private mutating func consume<T>(_ builder: () throws -> T) throws -> T {
        if isAtEnd {
            throw PlaceholderError.recursiveType("Unkeyed container exhausted")
        }
        defer { remaining -= 1 }
        return try builder()
    }

    mutating func decodeNil() throws -> Bool {
        try consume { false }
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
        try consume { false }
    }

    mutating func decode(_ type: String.Type) throws -> String {
        try consume { "" }
    }

    mutating func decode(_ type: Double.Type) throws -> Double {
        try consume { 0 }
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
        try consume { 0 }
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
        try consume { 0 }
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        try consume { 0 }
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        try consume { 0 }
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        try consume { 0 }
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        try consume { 0 }
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        try consume { 0 }
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        try consume { 0 }
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        try consume { 0 }
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        try consume { 0 }
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        try consume { 0 }
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try consume {
            if let known: T = try DefaultValueFactory.makeKnown(type) {
                return known
            }
            return try DefaultValueFactory.make(type)
        }
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let path = codingPath
        return try consume {
            let decoder = PlaceholderDecoder(codingPath: path)
            return try decoder.container(keyedBy: type)
        }
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let path = codingPath
        return try consume { PlaceholderUnkeyedContainer(codingPath: path) }
    }

    mutating func superDecoder() throws -> Decoder {
        let path = codingPath
        return try consume { PlaceholderDecoder(codingPath: path) }
    }
}

private struct PlaceholderSingleValueContainer: SingleValueDecodingContainer {
    let codingPath: [CodingKey]

    func decodeNil() -> Bool { true }

    func decode(_ type: Bool.Type) throws -> Bool { false }
    func decode(_ type: String.Type) throws -> String { "" }
    func decode(_ type: Double.Type) throws -> Double { 0 }
    func decode(_ type: Float.Type) throws -> Float { 0 }
    func decode(_ type: Int.Type) throws -> Int { 0 }
    func decode(_ type: Int8.Type) throws -> Int8 { 0 }
    func decode(_ type: Int16.Type) throws -> Int16 { 0 }
    func decode(_ type: Int32.Type) throws -> Int32 { 0 }
    func decode(_ type: Int64.Type) throws -> Int64 { 0 }
    func decode(_ type: UInt.Type) throws -> UInt { 0 }
    func decode(_ type: UInt8.Type) throws -> UInt8 { 0 }
    func decode(_ type: UInt16.Type) throws -> UInt16 { 0 }
    func decode(_ type: UInt32.Type) throws -> UInt32 { 0 }
    func decode(_ type: UInt64.Type) throws -> UInt64 { 0 }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        if let known: T = try DefaultValueFactory.makeKnown(type) {
            return known
        }
        return try DefaultValueFactory.make(type)
    }
}

private protocol AnyOptional {
    static func makeNil() -> Any
}

extension Optional: AnyOptional where Wrapped: Decodable {
    static func makeNil() -> Any { Optional<Wrapped>.none as Any }
}

private protocol AnyArray {
    static func sampleArray() throws -> Any
}

extension Array: AnyArray where Element: Decodable {
    static func sampleArray() throws -> Any {
        let element = try DefaultValueFactory.make(Element.self)
        return [element]
    }
}

private protocol AnyDictionary {
    static func emptyDictionary() -> Any
}

extension Dictionary: AnyDictionary where Key: Decodable, Value: Decodable {
    static func emptyDictionary() -> Any { [Key: Value]() }
}

private enum PlaceholderError: Error {
    case recursiveType(String)
}
