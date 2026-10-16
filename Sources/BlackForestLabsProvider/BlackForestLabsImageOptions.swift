import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct BlackForestLabsImageModelOptions: Sendable, Codable, Equatable {
    public var resolution: String?
    public var grounding: Bool?
    public var version: String?
    public var imagePrompt: String?
    public var imagePromptStrength: Double?
    public var steps: Int?
    public var guidance: Double?
    public var width: Int?
    public var height: Int?
    public var outputFormat: BlackForestLabsOutputFormat?
    public var promptUpsampling: Bool?
    public var raw: Bool?
    public var safetyTolerance: Int?
    public var webhookSecret: String?
    public var webhookUrl: String?
    public var pollIntervalMillis: Int?
    public var pollTimeoutMillis: Int?
    public init() {}
}

enum BFLImageAPI { case flux12, flux3, latest }

func bflImageOptions(_ options: SharedV4ProviderOptions?, api: BFLImageAPI, size: String?) async throws -> [String: JSONValue] {
    var properties: [String: JSONValue] = [:]
    for key in ["imagePrompt", "webhookSecret"] { properties[key] = .object(["type": .string("string")]) }
    for key in ["grounding", "promptUpsampling", "raw"] { properties[key] = .object(["type": .string("boolean")]) }
    properties["resolution"] = .object(["enum": .array(["768sq", "1k", "1.5k", "2k", "4k"].map(JSONValue.string))])
    properties["version"] = .object(["const": .string("latest")])
    properties["imagePromptStrength"] = .object(["type": .string("number"), "minimum": .number(0), "maximum": .number(1)])
    properties["guidance"] = .object(["type": .string("number"), "minimum": .number(0)])
    properties["outputFormat"] = .object(["enum": .array([.string("jpeg"), .string("png")])])
    properties["webhookUrl"] = .object(["type": .string("string"), "format": .string("uri")])
    for key in ["steps", "pollIntervalMillis", "pollTimeoutMillis"] {
        properties[key] = .object(["type": .string("integer"), "minimum": .number(1)])
    }
    if api == .latest { properties["steps"] = .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(16)]) }
    for key in ["width", "height"] {
        properties[key] = .object(["type": .string("integer"), "minimum": .number(api == .latest ? 64 : 256), "maximum": .number(api == .latest ? 6256 : 1920)])
    }
    properties["safetyTolerance"] = .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(api == .flux12 ? 6 : 7)])
    var providerOptions = options ?? [:]
    if api == .latest, let size {
        let parts = size.components(separatedBy: "x")
        let width = parts.first.flatMap(Double.init)
        let height = parts.count > 1 ? Double(parts[1]) : nil
        var dimensions: [String: JSONValue] = [
            "width": width.flatMap { $0.isFinite ? JSONValue.number($0) : nil } ?? .null,
            "height": height.flatMap { $0.isFinite ? JSONValue.number($0) : nil } ?? .null
        ]
        dimensions.merge(providerOptions["blackForestLabs"] ?? [:]) { _, value in value }
        providerOptions["blackForestLabs"] = dimensions
    }
    let parsed = try await parseProviderOptions(provider: "blackForestLabs", providerOptions: providerOptions, schema: FlexibleSchema(jsonSchema(.object(["type": .string("object"), "properties": .object(properties)]))))
    guard case .object(let values) = parsed else { return [:] }
    let result = values.filter { properties[$0.key] != nil }
    if api == .latest {
        let width = bflNumber(result["width"])
        let height = bflNumber(result["height"])
        guard (width == nil) == (height == nil), (width ?? 0) * (height ?? 0) <= 16_822_272 else {
            throw InvalidArgumentError(argument: "providerOptions", message: "invalid blackForestLabs provider options")
        }
    }
    return result
}
