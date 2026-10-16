import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct FireworksImageModelOptions: Codable, Sendable, Equatable {
    public enum OutputFormat: String, Codable, Sendable { case jpeg, png }
    public var guidanceScale: Double?
    public var numInferenceSteps: Int?
    public var outputFormat: OutputFormat?
    public var webhookUrl: String?
    public var webhookSecret: String?
    public var promptUpsampling: Bool?
    public var safetyTolerance: Int?
    public var cfgScale: Double?
    public var steps: Int?
    public var additionalOptions: JSONObject
    public init(guidanceScale: Double? = nil, numInferenceSteps: Int? = nil, outputFormat: OutputFormat? = nil, webhookUrl: String? = nil, webhookSecret: String? = nil, promptUpsampling: Bool? = nil, safetyTolerance: Int? = nil, cfgScale: Double? = nil, steps: Int? = nil, additionalOptions: JSONObject = [:]) {
        self.guidanceScale = guidanceScale; self.numInferenceSteps = numInferenceSteps; self.outputFormat = outputFormat; self.webhookUrl = webhookUrl; self.webhookSecret = webhookSecret; self.promptUpsampling = promptUpsampling; self.safetyTolerance = safetyTolerance; self.cfgScale = cfgScale; self.steps = steps; self.additionalOptions = additionalOptions
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case guidanceScale = "guidance_scale", numInferenceSteps = "num_inference_steps", outputFormat = "output_format", webhookUrl = "webhook_url", webhookSecret = "webhook_secret", promptUpsampling = "prompt_upsampling", safetyTolerance = "safety_tolerance", cfgScale = "cfg_scale", steps
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func optional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws -> T? { container.contains(key) ? try container.decode(type, forKey: key) : nil }
        guidanceScale = try optional(Double.self, .guidanceScale)
        numInferenceSteps = try optional(Int.self, .numInferenceSteps)
        outputFormat = try optional(OutputFormat.self, .outputFormat)
        webhookUrl = try optional(String.self, .webhookUrl)
        webhookSecret = try optional(String.self, .webhookSecret)
        promptUpsampling = try optional(Bool.self, .promptUpsampling)
        safetyTolerance = try optional(Int.self, .safetyTolerance)
        cfgScale = try optional(Double.self, .cfgScale)
        steps = try optional(Int.self, .steps)
        if let value = safetyTolerance, !(0...6).contains(value) { throw DecodingError.dataCorruptedError(forKey: .safetyTolerance, in: container, debugDescription: "Expected an integer between 0 and 6") }
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        additionalOptions = try JSONObject(from: decoder).filter { !known.contains($0.key) }
    }
    public func encode(to encoder: Encoder) throws {
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        var values = additionalOptions.filter { !known.contains($0.key) }
        if let guidanceScale { values["guidance_scale"] = .number(guidanceScale) }
        if let numInferenceSteps { values["num_inference_steps"] = .number(Double(numInferenceSteps)) }
        if let outputFormat { values["output_format"] = .string(outputFormat.rawValue) }
        if let webhookUrl { values["webhook_url"] = .string(webhookUrl) }
        if let webhookSecret { values["webhook_secret"] = .string(webhookSecret) }
        if let promptUpsampling { values["prompt_upsampling"] = .bool(promptUpsampling) }
        if let safetyTolerance { values["safety_tolerance"] = .number(Double(safetyTolerance)) }
        if let cfgScale { values["cfg_scale"] = .number(cfgScale) }
        if let steps { values["steps"] = .number(Double(steps)) }
        try values.encode(to: encoder)
    }
}

let fireworksImageModelOptionsSchema = FlexibleSchema(Schema<FireworksImageModelOptions>.codable(FireworksImageModelOptions.self, jsonSchema: .object(["type": .string("object")])))
