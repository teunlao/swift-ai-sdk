import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct KlingAIVideoModelOptions: Sendable, Equatable {
    public enum QualityMode: String, Sendable { case std, pro }
    public enum Sound: String, Sendable { case on, off }
    public enum ShotType: String, Sendable { case customize, intelligence }
    public enum CharacterOrientation: String, Sendable { case image, video }
    public enum KeepOriginalSound: String, Sendable { case yes, no }
    public var mode: QualityMode?
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var negativePrompt: String?
    public var sound: Sound?
    public var cfgScale: Double?
    public var cameraControl: JSONValue?
    public var imageTail: String?
    public var staticMask: String?
    public var dynamicMasks: JSONValue?
    public var multiShot: Bool?
    public var shotType: ShotType?
    public var multiPrompt: JSONValue?
    public var elementList: JSONValue?
    public var voiceList: JSONValue?
    public var videoUrl: String?
    public var characterOrientation: CharacterOrientation?
    public var keepOriginalSound: KeepOriginalSound?
    public var watermarkEnabled: Bool?
    public init() {}
}

let klingaiHandledOptions: Set<String> = ["mode", "pollIntervalMs", "pollTimeoutMs", "negativePrompt", "sound", "cfgScale", "cameraControl", "multiShot", "shotType", "multiPrompt", "elementList", "voiceList", "imageTail", "staticMask", "dynamicMasks", "videoUrl", "characterOrientation", "keepOriginalSound", "watermarkEnabled"]

private func nullable(_ type: String) -> JSONValue { .object(["type": .array([.string(type), .string("null")])]) }
private func enumeration(_ values: [String]) -> JSONValue { .object(["enum": .array(values.map(JSONValue.string) + [.null])]) }
private func array(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
    .object(["type": .array([.string("array"), .string("null")]), "items": .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string))])])
}

private let klingaiOptionsSchema: FlexibleSchema<JSONValue> = {
    var properties: [String: JSONValue] = [:]
    for key in ["negativePrompt", "imageTail", "staticMask", "videoUrl"] { properties[key] = nullable("string") }
    for key in ["multiShot", "watermarkEnabled"] { properties[key] = nullable("boolean") }
    for key in ["pollIntervalMs", "pollTimeoutMs"] { properties[key] = .object(["type": .array([.string("number"), .string("null")]), "exclusiveMinimum": .number(0)]) }
    properties["cfgScale"] = nullable("number")
    properties["mode"] = enumeration(["std", "pro"])
    properties["sound"] = enumeration(["on", "off"])
    properties["shotType"] = enumeration(["customize", "intelligence"])
    properties["characterOrientation"] = enumeration(["image", "video"])
    properties["keepOriginalSound"] = enumeration(["yes", "no"])
    let config = Dictionary(uniqueKeysWithValues: ["horizontal", "vertical", "pan", "tilt", "roll", "zoom"].map { ($0, nullable("number")) })
    properties["cameraControl"] = .object(["type": .array([.string("object"), .string("null")]), "required": .array([.string("type")]), "properties": .object([
        "type": .object(["enum": .array(["simple", "down_back", "forward_up", "right_turn_forward", "left_turn_forward"].map(JSONValue.string))]),
        "config": .object(["type": .array([.string("object"), .string("null")]), "properties": .object(config)])
    ])])
    properties["multiPrompt"] = array(["index": .object(["type": .string("number")]), "prompt": .object(["type": .string("string")]), "duration": .object(["type": .string("string")])], required: ["index", "prompt", "duration"])
    properties["elementList"] = array(["element_id": .object(["type": .string("number")])], required: ["element_id"])
    properties["voiceList"] = array(["voice_id": .object(["type": .string("string")])], required: ["voice_id"])
    var trajectory = array(["x": .object(["type": .string("number")]), "y": .object(["type": .string("number")])], required: ["x", "y"])
    if case .object(var object) = trajectory { object["type"] = .string("array"); trajectory = .object(object) }
    properties["dynamicMasks"] = array(["mask": .object(["type": .string("string")]), "trajectories": trajectory], required: ["mask", "trajectories"])
    return FlexibleSchema(jsonSchema(.object(["type": .string("object"), "properties": .object(properties)])))
}()

func klingaiOptions(_ options: SharedV4ProviderOptions?) async throws -> [String: JSONValue] {
    let parsed = try await parseProviderOptions(provider: "klingai", providerOptions: options, schema: klingaiOptionsSchema)
    guard case .object(var result) = parsed else { return [:] }
    func fields(_ value: JSONValue, _ keys: Set<String>) -> JSONValue {
        guard case .object(let object) = value else { return value }
        return .object(object.filter { keys.contains($0.key) })
    }
    if case .object(var camera) = result["cameraControl"] {
        if let config = camera["config"] { camera["config"] = fields(config, ["horizontal", "vertical", "pan", "tilt", "roll", "zoom"]) }
        result["cameraControl"] = fields(.object(camera), ["type", "config"])
    }
    for (key, keys) in ["multiPrompt": Set(["index", "prompt", "duration"]), "elementList": Set(["element_id"]), "voiceList": Set(["voice_id"])] {
        if case .array(let values) = result[key] { result[key] = .array(values.map { fields($0, keys) }) }
    }
    if case .array(let values) = result["dynamicMasks"] {
        result["dynamicMasks"] = .array(values.map { value in
            guard case .object(var object) = fields(value, ["mask", "trajectories"]) else { return value }
            if case .array(let points) = object["trajectories"] { object["trajectories"] = .array(points.map { fields($0, ["x", "y"]) }) }
            return .object(object)
        })
    }
    return result
}
