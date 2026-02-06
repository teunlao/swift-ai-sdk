import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-image-options.ts
// Upstream commit: f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9
//===----------------------------------------------------------------------===//

struct FalImageProviderOptions: Decodable, Sendable {
    let options: [String: JSONValue]
    let deprecatedKeys: [String]

    var useMultipleImages: Bool {
        if case .bool(let flag) = options["useMultipleImages"] {
            return flag
        }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawOptions = try container.decode([String: JSONValue].self)
        let normalized = try Self.normalize(rawOptions)
        self.options = normalized.options
        self.deprecatedKeys = normalized.deprecatedKeys
    }

    private static func normalize(_ rawOptions: [String: JSONValue]) throws -> (options: [String: JSONValue], deprecatedKeys: [String]) {
        var result: [String: JSONValue] = [:]
        var deprecatedKeys: [String] = []

        func mapKey(
            snakeKey: String,
            camelKey: String,
            validate: (String, JSONValue) throws -> JSONValue
        ) throws {
            if let snakeValue = nonNullValue(rawOptions[snakeKey]) {
                deprecatedKeys.append(snakeKey)
                result[camelKey] = try validate(snakeKey, snakeValue)
                return
            }

            if let camelValue = nonNullValue(rawOptions[camelKey]) {
                result[camelKey] = try validate(camelKey, camelValue)
            }
        }

        try mapKey(snakeKey: "image_url", camelKey: "imageUrl", validate: validateString)
        try mapKey(snakeKey: "mask_url", camelKey: "maskUrl", validate: validateString)
        try mapKey(snakeKey: "guidance_scale", camelKey: "guidanceScale") { key, value in
            try validateNumber(key, value, min: 1, max: 20)
        }
        try mapKey(snakeKey: "num_inference_steps", camelKey: "numInferenceSteps") { key, value in
            try validateNumber(key, value, min: 1, max: 50)
        }
        try mapKey(snakeKey: "enable_safety_checker", camelKey: "enableSafetyChecker", validate: validateBool)
        try mapKey(snakeKey: "output_format", camelKey: "outputFormat") { key, value in
            try validateEnum(key, value, allowed: ["jpeg", "png"])
        }
        try mapKey(snakeKey: "sync_mode", camelKey: "syncMode", validate: validateBool)
        try mapKey(snakeKey: "safety_tolerance", camelKey: "safetyTolerance", validate: validateSafetyTolerance)

        if let strength = nonNullValue(rawOptions["strength"]) {
            result["strength"] = try validateNumber("strength", strength, min: nil, max: nil)
        }
        if let acceleration = nonNullValue(rawOptions["acceleration"]) {
            result["acceleration"] = try validateEnum("acceleration", acceleration, allowed: ["none", "regular", "high"])
        }
        if let useMultipleImages = nonNullValue(rawOptions["useMultipleImages"]) {
            result["useMultipleImages"] = try validateBool("useMultipleImages", useMultipleImages)
        }

        for (key, value) in rawOptions where !knownKeys.contains(key) {
            result[key] = value
        }

        return (options: result, deprecatedKeys: deprecatedKeys)
    }
}

let falImageProviderOptionsSchema = FlexibleSchema(
    Schema<FalImageProviderOptions>.codable(
        FalImageProviderOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let knownKeys: Set<String> = [
    // camelCase keys
    "imageUrl",
    "maskUrl",
    "guidanceScale",
    "numInferenceSteps",
    "enableSafetyChecker",
    "outputFormat",
    "syncMode",
    "strength",
    "acceleration",
    "safetyTolerance",
    "useMultipleImages",
    // snake_case keys
    "image_url",
    "mask_url",
    "guidance_scale",
    "num_inference_steps",
    "enable_safety_checker",
    "output_format",
    "sync_mode",
    "safety_tolerance",
]

private func nonNullValue(_ value: JSONValue?) -> JSONValue? {
    guard let value, value != .null else {
        return nil
    }
    return value
}

private func validateString(_ key: String, _ value: JSONValue) throws -> JSONValue {
    guard case .string = value else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a string"))
    }
    return value
}

private func validateBool(_ key: String, _ value: JSONValue) throws -> JSONValue {
    guard case .bool = value else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a boolean"))
    }
    return value
}

private func validateNumber(_ key: String, _ value: JSONValue, min: Double?, max: Double?) throws -> JSONValue {
    guard case .number(let number) = value else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a number"))
    }
    if let min, number < min {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be >= \(min)"))
    }
    if let max, number > max {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be <= \(max)"))
    }
    return value
}

private func validateEnum(_ key: String, _ value: JSONValue, allowed: Set<String>) throws -> JSONValue {
    guard case .string(let string) = value else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a string"))
    }
    guard allowed.contains(string) else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid '\(key)' value: \(string)"))
    }
    return value
}

private func validateSafetyTolerance(_ key: String, _ value: JSONValue) throws -> JSONValue {
    switch value {
    case .string(let string):
        let allowed: Set<String> = ["1", "2", "3", "4", "5", "6"]
        guard allowed.contains(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid '\(key)' value: \(string)"))
        }
        return value
    case .number(let number):
        if number < 1 || number > 6 {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be between 1 and 6"))
        }
        return value
    default:
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a string or number"))
    }
}

