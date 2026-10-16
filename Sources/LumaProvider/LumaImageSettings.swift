import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum LumaReferenceType: String, Sendable, Codable {
    case image, style, character
    case modifyImage = "modify_image"
}

public struct LumaImageConfig: Sendable, Codable, Equatable {
    public var weight: Double?
    public var id: String?
    public init(weight: Double? = nil, id: String? = nil) {
        self.weight = weight
        self.id = id
    }
}

public struct LumaImageModelOptions: Sendable, Codable {
    public var pollIntervalMillis: Double?
    public var maxPollAttempts: Double?
    public var referenceType: LumaReferenceType?
    public var images: [LumaImageConfig]?

    public init(pollIntervalMillis: Double? = nil, maxPollAttempts: Double? = nil, referenceType: LumaReferenceType? = nil, images: [LumaImageConfig]? = nil) {
        self.pollIntervalMillis = pollIntervalMillis
        self.maxPollAttempts = maxPollAttempts
        self.referenceType = referenceType
        self.images = images
    }
}

let lumaImageModelOptionsSchema = FlexibleSchema(jsonSchema(.object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "pollIntervalMillis": .object(["type": .array([.string("number"), .string("null")])]),
        "maxPollAttempts": .object(["type": .array([.string("number"), .string("null")])]),
        "referenceType": .object(["enum": .array([.string("image"), .string("style"), .string("character"), .string("modify_image"), .null])]),
        "images": .object([
            "type": .array([.string("array"), .string("null")]),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "weight": .object(["type": .array([.string("number"), .string("null")]), "minimum": .number(0), "maximum": .number(1)]),
                    "id": .object(["type": .array([.string("string"), .string("null")])])
                ])
            ])
        ])
    ])
])))
