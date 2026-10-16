import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum BlackForestLabsVideoKeyframe: Sendable, Equatable, Codable {
    case image(String)
    case timed(seconds: Double, image: String)
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .image(value); return }
        var tuple = try decoder.unkeyedContainer()
        let seconds = try tuple.decode(Double.self)
        let image = try tuple.decode(String.self)
        guard tuple.isAtEnd, (0...20).contains(seconds) else { throw DecodingError.dataCorruptedError(in: tuple, debugDescription: "Invalid timed keyframe") }
        self = .timed(seconds: seconds, image: image)
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .image(let value): var container = encoder.singleValueContainer(); try container.encode(value)
        case .timed(let seconds, let image): var container = encoder.unkeyedContainer(); try container.encode(seconds); try container.encode(image)
        }
    }
}

public struct BlackForestLabsVideoModelOptions: Sendable, Codable {
    public var resolution: String?
    public var aspectRatio: String?
    public var keyframes: [BlackForestLabsVideoKeyframe]?
    public var safetyTolerance: Int?
    public var draft: Bool?
    public var draftCache: String?
    public var version: String?
    public init() {}
}

let bflVideoAspectRatios = ["21:9", "2:1", "16:9", "4:3", "1:1", "3:4", "9:16", "auto"]

func bflVideoOptions(_ options: SharedV4ProviderOptions?) async throws -> [String: JSONValue] {
    let properties: [String: JSONValue] = [
        "resolution": .object(["enum": .array([.string("hd"), .string("fhd")])]),
        "aspectRatio": .object(["enum": .array(bflVideoAspectRatios.map(JSONValue.string))]),
        "keyframes": .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(10)]),
        "safetyTolerance": .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(4)]),
        "draft": .object(["type": .string("boolean")]),
        "draftCache": .object(["type": .string("string")]),
        "version": .object(["const": .string("latest")])
    ]
    let parsed = try await parseProviderOptions(provider: "blackForestLabs", providerOptions: options, schema: FlexibleSchema(jsonSchema(.object(["type": .string("object"), "properties": .object(properties)]))))
    guard case .object(let values) = parsed else { return [:] }
    let result = values.filter { properties[$0.key] != nil }
    if let keyframes = result["keyframes"] {
        do {
            let frames = try JSONDecoder().decode([BlackForestLabsVideoKeyframe].self, from: JSONEncoder().encode(keyframes))
            let timed = frames.compactMap { value -> Double? in if case .timed(let seconds, _) = value { return seconds }; return nil }
            guard timed.isEmpty || timed.count == frames.count,
                  zip(timed, timed.dropFirst()).allSatisfy({ $0 < $1 }) else { throw InvalidArgumentError(argument: "keyframes", message: "Timed keyframes must be in chronological order.") }
        } catch { throw InvalidArgumentError(argument: "providerOptions", message: "invalid blackForestLabs provider options", cause: error) }
    }
    return result
}
