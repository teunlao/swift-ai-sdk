import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct DeepInfraImageModelOptions: Codable, Sendable, Equatable {
    public var negative_prompt: String?
    public var num_inference_steps: Double?
    public var guidance_scale: Double?
    public var guidance: Double?
    public var response_format: String?
    public var quality: String?
    public var style: String?
    public var user: String?
    public init() {}
}

let deepInfraImageModelOptionsSchema = FlexibleSchema(Schema<[String: JSONValue]>(
    jsonSchemaResolver: { ["type": "object"] }, validator: { value in
        do {
            let json = try jsonValue(from: value)
            guard case .object(let options) = json else { throw DeepInfraImageOptionsError() }
            for key in ["negative_prompt", "quality", "style", "user"] {
                if let value = options[key], value != .null {
                    guard case .string = value else { throw DeepInfraImageOptionsError() }
                }
            }
            for key in ["num_inference_steps", "guidance_scale", "guidance"] {
                if let value = options[key], value != .null {
                    guard case .number(let number) = value, number.isFinite else { throw DeepInfraImageOptionsError() }
                }
            }
            if let format = options["response_format"], format != .null, format != "b64_json" { throw DeepInfraImageOptionsError() }
            return .success(value: options)
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))
private struct DeepInfraImageOptionsError: Error {}
