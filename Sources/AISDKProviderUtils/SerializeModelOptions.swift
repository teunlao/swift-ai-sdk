import Foundation
import AISDKProvider

/// Synchronous headers resolver used during model option serialization.
public typealias ModelOptionsHeadersResolver = @Sendable () throws -> [String: String?]

/// Async headers resolvers cannot cross the synchronous workflow serialization boundary.
public typealias AsyncModelOptionsHeadersResolver = @Sendable () async throws -> [String: String?]

/// Serialized model options that can cross workflow step boundaries.
public struct SerializedModelOptions: Equatable, Codable, Sendable {
    public let modelId: String
    public let config: JSONObject

    public init(modelId: String, config: JSONObject) {
        self.modelId = modelId
        self.config = config
    }
}

/// Options for `serializeModelOptions`.
public struct SerializeModelOptionsOptions {
    public let modelId: String
    public let config: [String: Any?]

    public init(modelId: String, config: [String: Any?]) {
        self.modelId = modelId
        self.config = config
    }
}

/// Error thrown when model options cannot be serialized synchronously.
public struct SerializeModelOptionsError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }

    public static let promiseReturnedFromResolveSync = SerializeModelOptionsError(
        message: "Promise returned from resolveSync"
    )
}

/// Serializes a model instance for workflow step boundaries.
///
/// Non-JSON config values are omitted. The `headers` key is the only key whose
/// synchronous function value is resolved before JSON serializability is tested.
public func serializeModelOptions(
    _ options: SerializeModelOptionsOptions
) throws -> SerializedModelOptions {
    try serializeModelOptions(modelId: options.modelId, config: options.config)
}

/// Serializes a model instance for workflow step boundaries.
public func serializeModelOptions(
    modelId: String,
    config: [String: Any?]
) throws -> SerializedModelOptions {
    var serializableConfig: JSONObject = [:]
    serializableConfig.reserveCapacity(config.count)

    for (key, value) in config {
        let resolvedValue: Any?

        if key == "headers" {
            resolvedValue = try resolveHeadersValue(value)
        } else {
            resolvedValue = value
        }

        guard let jsonValue = jsonSerializableValue(from: resolvedValue) else {
            continue
        }

        serializableConfig[key] = jsonValue
    }

    return SerializedModelOptions(modelId: modelId, config: serializableConfig)
}

private func resolveHeadersValue(_ value: Any?) throws -> Any? {
    if value == nil {
        return nil
    }

    if let resolver = value as? ModelOptionsHeadersResolver {
        return try resolver()
    }

    if value is AsyncModelOptionsHeadersResolver {
        throw SerializeModelOptionsError.promiseReturnedFromResolveSync
    }

    return value
}

private func jsonSerializableValue(from value: Any?) -> JSONValue? {
    guard let value else {
        return nil
    }

    if let optional = value as? AnyOptional {
        guard !optional.isNil else {
            return nil
        }
    }

    if let jsonValue = value as? JSONValue {
        return jsonValue
    }

    if value is NSNull {
        return .null
    }

    if let bool = value as? Bool {
        return .bool(bool)
    }

    if let string = value as? String {
        return .string(string)
    }

    if let number = numberJSONValue(from: value) {
        return number
    }

    if let dictionary = value as? [String: Any?] {
        return jsonSerializableObject(from: dictionary)
    }

    if let dictionary = value as? [String: Any] {
        return jsonSerializableObject(from: dictionary.mapValues { Optional.some($0) })
    }

    if let array = value as? [Any?] {
        return jsonSerializableArray(from: array)
    }

    if let array = value as? [Any] {
        return jsonSerializableArray(from: array.map { Optional.some($0) })
    }

    return nil
}

private func numberJSONValue(from value: Any) -> JSONValue? {
    if let int = value as? Int {
        return .number(Double(int))
    }

    if let int = value as? Int8 {
        return .number(Double(int))
    }

    if let int = value as? Int16 {
        return .number(Double(int))
    }

    if let int = value as? Int32 {
        return .number(Double(int))
    }

    if let int = value as? Int64 {
        return .number(Double(int))
    }

    if let uint = value as? UInt {
        return .number(Double(uint))
    }

    if let uint = value as? UInt8 {
        return .number(Double(uint))
    }

    if let uint = value as? UInt16 {
        return .number(Double(uint))
    }

    if let uint = value as? UInt32 {
        return .number(Double(uint))
    }

    if let uint = value as? UInt64 {
        return .number(Double(uint))
    }

    if let float = value as? Float {
        guard float.isFinite else { return nil }
        return .number(Double(float))
    }

    if let double = value as? Double {
        guard double.isFinite else { return nil }
        return .number(double)
    }

    if let number = value as? NSNumber {
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }

        let double = number.doubleValue
        guard double.isFinite else { return nil }
        return .number(double)
    }

    return nil
}

private func jsonSerializableObject(from object: [String: Any?]) -> JSONValue? {
    var result: [String: JSONValue] = [:]
    result.reserveCapacity(object.count)

    for (key, value) in object {
        if let optional = value as? AnyOptional, optional.isNil {
            continue
        }

        guard value != nil else {
            continue
        }

        guard let jsonValue = jsonSerializableValue(from: value) else {
            return nil
        }

        result[key] = jsonValue
    }

    return .object(result)
}

private func jsonSerializableArray(from array: [Any?]) -> JSONValue? {
    var result: [JSONValue] = []
    result.reserveCapacity(array.count)

    for value in array {
        if let optional = value as? AnyOptional, optional.isNil {
            result.append(.null)
            continue
        }

        guard let value else {
            result.append(.null)
            continue
        }

        guard let jsonValue = jsonSerializableValue(from: value) else {
            return nil
        }

        result.append(jsonValue)
    }

    return .array(result)
}

private protocol AnyOptional {
    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    fileprivate var isNil: Bool {
        switch self {
        case .none:
            return true
        case .some:
            return false
        }
    }
}
