import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIImageGenerationArgs: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable { case auto, generate, edit }
    public var action: Action?
    public init(action: Action? = nil) { self.action = action }
}

let xaiImageGenerationArgsSchema = FlexibleSchema(Schema<XAIImageGenerationArgs>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        guard case .object(let object) = json, object["action"] != .null else { throw InvalidArgumentError(argument: "action", message: "Expected auto, generate, or edit") }
        return .success(value: try JSONDecoder().decode(XAIImageGenerationArgs.self, from: JSONEncoder().encode(json)))
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

let xaiImageGenerationToolFactory = createProviderExecutedToolFactory(
    id: "xai.image_generation", name: "image_generation",
    inputSchema: hostedToolInputSchema,
    outputSchema: FlexibleSchema(jsonSchema(.object([
        "type": .string("object"), "required": .array([.string("result")]),
        "properties": .object(["result": .object(["type": .string("string")]), "prompt": .object(["type": .string("string")])])
    ])))
) { (args: XAIImageGenerationArgs) in
    ProviderExecutedToolFactoryOptions(args: args.action.map { ["action": .string($0.rawValue)] } ?? [:])
}

public func imageGeneration(_ args: XAIImageGenerationArgs = .init()) -> Tool { xaiImageGenerationToolFactory(args) }
