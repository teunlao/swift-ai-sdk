import Foundation
import AISDKProvider
import AISDKProviderUtils

public let openAIImageModelMaxImagesPerCall: [OpenAIImageModelId: Int] = [
    "dall-e-3": 1,
    "dall-e-2": 10,
    "gpt-image-1": 10,
    "gpt-image-1-mini": 10,
    "gpt-image-1.5": 10,
    "gpt-image-2": 10,
    "chatgpt-image-latest": 10
]

private let openAIDefaultImageResponseFormatPrefixes: [String] = [
    "chatgpt-image-",
    "gpt-image-1-mini",
    "gpt-image-1.5",
    "gpt-image-1",
    "gpt-image-2"
]

func openAIImageHasDefaultResponseFormat(modelId: OpenAIImageModelId) -> Bool {
    openAIDefaultImageResponseFormatPrefixes.contains { modelId.rawValue.hasPrefix($0) }
}

public struct OpenAIImageModelOptions: Sendable, Equatable {
    public var quality: String?
    public var background: String?
    public var outputFormat: String?
    public var outputCompression: Double?
    public var user: String?

    public init(
        quality: String? = nil,
        background: String? = nil,
        outputFormat: String? = nil,
        outputCompression: Double? = nil,
        user: String? = nil
    ) {
        self.quality = quality
        self.background = background
        self.outputFormat = outputFormat
        self.outputCompression = outputCompression
        self.user = user
    }
}

public struct OpenAIImageModelGenerationOptions: Sendable, Equatable {
    public var quality: String?
    public var background: String?
    public var outputFormat: String?
    public var outputCompression: Double?
    public var user: String?
    public var style: String?
    public var moderation: String?

    public init(
        quality: String? = nil,
        background: String? = nil,
        outputFormat: String? = nil,
        outputCompression: Double? = nil,
        user: String? = nil,
        style: String? = nil,
        moderation: String? = nil
    ) {
        self.quality = quality
        self.background = background
        self.outputFormat = outputFormat
        self.outputCompression = outputCompression
        self.user = user
        self.style = style
        self.moderation = moderation
    }
}

public struct OpenAIImageModelEditOptions: Sendable, Equatable {
    public var quality: String?
    public var background: String?
    public var outputFormat: String?
    public var outputCompression: Double?
    public var user: String?
    public var inputFidelity: String?

    public init(
        quality: String? = nil,
        background: String? = nil,
        outputFormat: String? = nil,
        outputCompression: Double? = nil,
        user: String? = nil,
        inputFidelity: String? = nil
    ) {
        self.quality = quality
        self.background = background
        self.outputFormat = outputFormat
        self.outputCompression = outputCompression
        self.user = user
        self.inputFidelity = inputFidelity
    }
}

private let qualityValues = ["standard", "hd", "low", "medium", "high", "auto"]
private let backgroundValues = ["transparent", "opaque", "auto"]
private let outputFormatValues = ["png", "jpeg", "webp"]
private let styleValues = ["vivid", "natural"]
private let moderationValues = ["auto", "low"]
private let inputFidelityValues = ["high", "low"]

private func enumSchema(_ values: [String]) -> JSONValue {
    .object([
        "type": .string("string"),
        "enum": .array(values.map { .string($0) })
    ])
}

private let outputCompressionSchema: JSONValue = .object([
    "type": .string("integer"),
    "minimum": .number(0),
    "maximum": .number(100)
])

private func openAIImageOptionsJSONSchema(extraProperties: [String: JSONValue]) -> JSONValue {
    var properties: [String: JSONValue] = [
        "quality": enumSchema(qualityValues),
        "background": enumSchema(backgroundValues),
        "outputFormat": enumSchema(outputFormatValues),
        "outputCompression": outputCompressionSchema,
        "user": .object(["type": .string("string")])
    ]

    for (key, value) in extraProperties {
        properties[key] = value
    }

    return .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object(properties)
    ])
}

private func imageOptionsField(_ dict: [String: JSONValue], key: String, message: String) throws -> JSONValue? {
    guard let value = dict[key] else { return nil }
    guard value != .null else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: message)
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return value
}

private func parseImageOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = try imageOptionsField(dict, key: key, message: "\(key) must be a string") else {
        return nil
    }
    guard case .string(let string) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return string
}

private func parseImageOptionalEnum(
    _ dict: [String: JSONValue],
    key: String,
    values: [String]
) throws -> String? {
    let issue = "\(key) must be one of \(values.joined(separator: ", "))"
    guard let value = try imageOptionsField(dict, key: key, message: issue) else {
        return nil
    }
    guard case .string(let string) = value, values.contains(string) else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: issue)
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return string
}

private func parseImageOptionalInteger(
    _ dict: [String: JSONValue],
    key: String,
    min: Double,
    max: Double
) throws -> Double? {
    guard let value = try imageOptionsField(dict, key: key, message: "\(key) must be an integer") else {
        return nil
    }
    guard case .number(let number) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be an integer")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    guard number.rounded(.towardZero) == number else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be an integer")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    guard number >= min, number <= max else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be between \(Int(min)) and \(Int(max))")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return number
}

private let openAIImageModelGenerationOptionsJSONSchema = openAIImageOptionsJSONSchema(extraProperties: [
    "style": enumSchema(styleValues),
    "moderation": enumSchema(moderationValues)
])

private let openAIImageModelEditOptionsJSONSchema = openAIImageOptionsJSONSchema(extraProperties: [
    "inputFidelity": enumSchema(inputFidelityValues)
])

let openAIImageModelGenerationOptionsSchema = FlexibleSchema<OpenAIImageModelGenerationOptions>(
    Schema(
        jsonSchemaResolver: { openAIImageModelGenerationOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                return .success(value: OpenAIImageModelGenerationOptions(
                    quality: try parseImageOptionalEnum(dict, key: "quality", values: qualityValues),
                    background: try parseImageOptionalEnum(dict, key: "background", values: backgroundValues),
                    outputFormat: try parseImageOptionalEnum(dict, key: "outputFormat", values: outputFormatValues),
                    outputCompression: try parseImageOptionalInteger(dict, key: "outputCompression", min: 0, max: 100),
                    user: try parseImageOptionalString(dict, key: "user"),
                    style: try parseImageOptionalEnum(dict, key: "style", values: styleValues),
                    moderation: try parseImageOptionalEnum(dict, key: "moderation", values: moderationValues)
                ))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

let openAIImageModelEditOptionsSchema = FlexibleSchema<OpenAIImageModelEditOptions>(
    Schema(
        jsonSchemaResolver: { openAIImageModelEditOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                return .success(value: OpenAIImageModelEditOptions(
                    quality: try parseImageOptionalEnum(dict, key: "quality", values: qualityValues),
                    background: try parseImageOptionalEnum(dict, key: "background", values: backgroundValues),
                    outputFormat: try parseImageOptionalEnum(dict, key: "outputFormat", values: outputFormatValues),
                    outputCompression: try parseImageOptionalInteger(dict, key: "outputCompression", min: 0, max: 100),
                    user: try parseImageOptionalString(dict, key: "user"),
                    inputFidelity: try parseImageOptionalEnum(dict, key: "inputFidelity", values: inputFidelityValues)
                ))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
