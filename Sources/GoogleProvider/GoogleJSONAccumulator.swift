import Foundation
import AISDKProvider

struct GooglePartialArg: Codable, Sendable {
    let jsonPath: String
    let stringValue: String?
    let numberValue: Double?
    let boolValue: Bool?
    let nullValue: JSONValue?
    let willContinue: Bool?

    private enum CodingKeys: String, CodingKey { case jsonPath, stringValue, numberValue, boolValue, nullValue, willContinue }
    let hasNullValue: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonPath = try container.decode(String.self, forKey: .jsonPath)
        stringValue = try container.decodeIfPresent(String.self, forKey: .stringValue)
        numberValue = try container.decodeIfPresent(Double.self, forKey: .numberValue)
        boolValue = try container.decodeIfPresent(Bool.self, forKey: .boolValue)
        nullValue = try container.decodeIfPresent(JSONValue.self, forKey: .nullValue)
        willContinue = try container.decodeIfPresent(Bool.self, forKey: .willContinue)
        hasNullValue = container.contains(.nullValue)
    }
}

struct GoogleJSONAccumulator {
    private enum Segment: Hashable { case key(String); case index(Int) }
    private struct Container { let segment: Segment; let array: Bool; var count: Int = 0 }
    private var stack: [Container] = []
    private var accumulated: JSONValue = .object([:])
    private var keyOrder: [[Segment]: [String]] = [:]
    private var stringOpen = false
    private var text = ""

    mutating func process(_ args: [GooglePartialArg]) throws -> String {
        var delta = ""
        for arg in args {
            let path = arg.jsonPath.hasPrefix("$.") ? String(arg.jsonPath.dropFirst(2)) : arg.jsonPath
            guard !path.isEmpty else { continue }
            let segments = parsePath(path)
            guard let leaf = segments.last else { continue }
            if let string = arg.stringValue, let existing = get(accumulated, path: segments[...]) {
                accumulated = set(accumulated, path: segments[...], prefix: [], value: .string(try jsString(existing) + string))
                delta += String(try googleJSONString(.string(string)).dropFirst().dropLast())
                continue
            }
            let value: JSONValue
            if let string = arg.stringValue { value = .string(string) }
            else if let number = arg.numberValue { value = .number(number) }
            else if let bool = arg.boolValue { value = .bool(bool) }
            else if arg.hasNullValue { value = .null }
            else { continue }
            accumulated = set(accumulated, path: segments[...], prefix: [], value: value)
            if stringOpen { delta += "\""; stringOpen = false }
            if stack.isEmpty { stack.append(.init(segment: .key(""), array: false)); delta += "{" }
            let target = Array(segments.dropLast())
            var common = 0
            while common < min(stack.count - 1, target.count), stack[common + 1].segment == target[common] { common += 1 }
            while stack.count > common + 1 { delta += stack.removeLast().array ? "]" : "}" }
            for index in (stack.count - 1)..<target.count {
                let segment = target[index]
                if stack[stack.count - 1].count > 0 { delta += "," }
                stack[stack.count - 1].count += 1
                if case .key(let key) = segment { delta += try googleJSONString(.string(key)) + ":" }
                let next = index + 1 < target.count ? target[index + 1] : leaf
                let array: Bool
                if case .index = next { array = true } else { array = false }
                delta += array ? "[" : "{"
                stack.append(.init(segment: segment, array: array))
            }
            if stack[stack.count - 1].count > 0 { delta += "," }
            stack[stack.count - 1].count += 1
            if case .key(let key) = leaf { delta += try googleJSONString(.string(key)) + ":" }
            let serialized = try googleJSONString(value)
            if arg.stringValue != nil && arg.willContinue == true {
                delta += serialized.dropLast()
                stringOpen = true
            } else { delta += serialized }
        }
        text += delta
        return delta
    }

    func finalize() throws -> (json: String, closing: String) {
        let json = try serialize(accumulated, path: [])
        let offset = min(text.utf16.count, json.utf16.count)
        return (json, String(decoding: json.utf16.dropFirst(offset), as: UTF16.self))
    }

    private func get(_ value: JSONValue, path: ArraySlice<Segment>) -> JSONValue? {
        guard let first = path.first else { return value }
        switch (value, first) {
        case (.object(let object), .key(let key)): return object[key].flatMap { get($0, path: path.dropFirst()) }
        case (.array(let values), .index(let index)): return values.indices.contains(index) ? get(values[index], path: path.dropFirst()) : nil
        default: return nil
        }
    }

    private mutating func set(_ current: JSONValue, path: ArraySlice<Segment>, prefix: [Segment], value: JSONValue) -> JSONValue {
        guard let first = path.first else { return value }
        switch first {
        case .key(let key):
            var object: JSONObject
            if case .object(let existing) = current { object = existing }
            else { object = [:]; keyOrder[prefix] = [] }
            if object[key] == nil { keyOrder[prefix, default: []].append(key) }
            let initial: JSONValue
            if case .index? = path.dropFirst().first { initial = .array([]) } else { initial = .object([:]) }
            object[key] = set(object[key] ?? initial, path: path.dropFirst(), prefix: prefix + [first], value: value)
            return .object(object)
        case .index(let index):
            var values: [JSONValue]
            if case .array(let existing) = current { values = existing } else { values = [] }
            while values.count <= index { values.append(.null) }
            let initial: JSONValue
            if case .index? = path.dropFirst().first { initial = .array([]) } else { initial = .object([:]) }
            values[index] = set(values[index] == .null ? initial : values[index], path: path.dropFirst(), prefix: prefix + [first], value: value)
            return .array(values)
        }
    }

    private func serialize(_ value: JSONValue, path: [Segment]) throws -> String {
        switch value {
        case .object(let object):
            var numeric: [(String, UInt32)] = []
            var ordinary: [String] = []
            for key in keyOrder[path] ?? Array(object.keys) {
                if let index = UInt32(key), String(index) == key, index != UInt32.max { numeric.append((key, index)) }
                else { ordinary.append(key) }
            }
            let keys = numeric.sorted { $0.1 < $1.1 }.map(\.0) + ordinary
            return try "{" + keys.compactMap { key in try object[key].map { try googleJSONString(.string(key)) + ":" + serialize($0, path: path + [.key(key)]) } }.joined(separator: ",") + "}"
        case .array(let values): return try "[" + values.enumerated().map { try serialize($0.element, path: path + [.index($0.offset)]) }.joined(separator: ",") + "]"
        default: return try googleJSONString(value)
        }
    }

    private func jsString(_ value: JSONValue) throws -> String {
        switch value {
        case .string(let value): return value
        case .object: return "[object Object]"
        case .array(let values): return try values.map { $0 == .null ? "" : try jsString($0) }.joined(separator: ",")
        default: return try googleJSONString(value)
        }
    }

    private func parsePath(_ raw: String) -> [Segment] {
        var result: [Segment] = []
        for part in raw.split(separator: ".", omittingEmptySubsequences: false) {
            guard let bracket = part.firstIndex(of: "[") else { result.append(.key(String(part))); continue }
            if bracket != part.startIndex { result.append(.key(String(part[..<bracket]))) }
            let suffix = String(part[bracket...])
            let regex = try! NSRegularExpression(pattern: "\\[(\\d+)\\]")
            for match in regex.matches(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)) {
                if let range = Range(match.range(at: 1), in: suffix), let index = Int(suffix[range]) { result.append(.index(index)) }
            }
        }
        return result
    }
}
