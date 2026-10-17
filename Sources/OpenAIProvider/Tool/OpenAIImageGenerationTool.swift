import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIImageGenerationArgs: Sendable, Equatable {
    public struct InputImageMask: Sendable, Equatable {
        public let fileId: String?
        public let imageUrl: String?

        public init(fileId: String? = nil, imageUrl: String? = nil) {
            self.fileId = fileId
            self.imageUrl = imageUrl
        }
    }

    public let action: String?
    public let background: String?
    public let inputFidelity: String?
    public let inputImageMask: InputImageMask?
    public let model: String?
    public let moderation: String?
    public let outputCompression: Int?
    public let outputFormat: String?
    public let partialImages: Int?
    public let quality: String?
    public let size: String?

    public init(
        action: String? = nil,
        background: String? = nil,
        inputFidelity: String? = nil,
        inputImageMask: InputImageMask? = nil,
        model: String? = nil,
        moderation: String? = nil,
        outputCompression: Int? = nil,
        outputFormat: String? = nil,
        partialImages: Int? = nil,
        quality: String? = nil,
        size: String? = nil
    ) {
        self.action = action
        self.background = background
        self.inputFidelity = inputFidelity
        self.inputImageMask = inputImageMask
        self.model = model
        self.moderation = moderation
        self.outputCompression = outputCompression
        self.outputFormat = outputFormat
        self.partialImages = partialImages
        self.quality = quality
        self.size = size
    }
}

private let imageGenerationArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "action": .object(["type": .string("string"), "enum": .array([.string("generate"), .string("edit"), .string("auto")])]),
        "background": .object([
            "type": .string("string"),
            "enum": .array([.string("auto"), .string("opaque"), .string("transparent")])
        ]),
        "inputFidelity": .object([
            "type": .string("string"),
            "enum": .array([.string("low"), .string("high")])
        ]),
        "inputImageMask": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "fileId": .object([
                    "type": .string("string")
                ]),
                "imageUrl": .object([
                    "type": .string("string")
                ])
            ])
        ]),
        "model": .object([
            "type": .string("string")
        ]),
        "moderation": .object([
            "type": .string("string"),
            "enum": .array([.string("auto"), .string("low")])
        ]),
        "outputCompression": .object([
            "type": .string("integer"), "minimum": .number(0), "maximum": .number(100)
        ]),
        "outputFormat": .object([
            "type": .string("string"),
            "enum": .array([.string("png"), .string("jpeg"), .string("webp")])
        ]),
        "partialImages": .object([
            "type": .string("integer"), "minimum": .number(0), "maximum": .number(3)
        ]),
        "quality": .object([
            "type": .string("string"),
            "enum": .array([.string("auto"), .string("low"), .string("medium"), .string("high"), .string("xhigh"), .string("max")])
        ]),
        "size": .object([
            "type": .string("string"),
            "anyOf": .array([
                .object(["enum": .array([.string("auto"), .string("1024x1024"), .string("1024x1536"), .string("1536x1024")])]),
                .object(["type": .string("string"), "pattern": .string("^[0-9]+x[0-9]+$")])
            ])
        ])
    ])
])

public let openaiImageGenerationArgsSchema = FlexibleSchema<OpenAIImageGenerationArgs>(
    Schema(
        jsonSchemaResolver: { imageGenerationArgsJSONSchema },
        validator: { value in
            do {
                let json = try await validateTypes(ValidateTypesOptions(value: value, schema: openAIToolSchema(imageGenerationArgsJSONSchema, strict: true)))
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func optionalString(_ key: String, allowed: [String]? = nil) throws -> String? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .string(let string) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
                        throw TypeValidationError.wrap(value: raw, cause: error)
                    }
                    if let allowed, !allowed.contains(string) {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be one of \(allowed.joined(separator: ", "))")
                        throw TypeValidationError.wrap(value: raw, cause: error)
                    }
                    return string
                }

                func optionalInt(_ key: String, min: Int, max: Int) throws -> Int? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .number(let number) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a number")
                        throw TypeValidationError.wrap(value: raw, cause: error)
                    }
                    guard let intValue = Int(exactly: number), intValue >= min, intValue <= max else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be between \(min) and \(max)")
                        throw TypeValidationError.wrap(value: raw, cause: error)
                    }
                    return intValue
                }

                var mask: OpenAIImageGenerationArgs.InputImageMask? = nil
                if let maskValue = dict["inputImageMask"], maskValue != .null {
                    guard case .object(let maskObject) = maskValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "inputImageMask must be an object")
                        return .failure(error: TypeValidationError.wrap(value: maskValue, cause: error))
                    }
                    var fileId: String? = nil
                    if let fileIdValue = maskObject["fileId"], fileIdValue != .null {
                        guard case .string(let string) = fileIdValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "inputImageMask.fileId must be a string")
                            return .failure(error: TypeValidationError.wrap(value: fileIdValue, cause: error))
                        }
                        fileId = string
                    }
                    var imageUrl: String? = nil
                    if let imageUrlValue = maskObject["imageUrl"], imageUrlValue != .null {
                        guard case .string(let string) = imageUrlValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "inputImageMask.imageUrl must be a string")
                            return .failure(error: TypeValidationError.wrap(value: imageUrlValue, cause: error))
                        }
                        imageUrl = string
                    }
                    mask = OpenAIImageGenerationArgs.InputImageMask(fileId: fileId, imageUrl: imageUrl)
                }

                let size = try optionalString("size")
                if let size, size != "auto", size.range(of: #"^[0-9]+x[0-9]+\z"#, options: .regularExpression) == nil {
                    throw TypeValidationError.wrap(value: size, cause: SchemaValidationIssuesError(vendor: "openai", issues: "size must be auto or WIDTHxHEIGHT"))
                }
                let args = OpenAIImageGenerationArgs(
                    action: try optionalString("action", allowed: ["generate", "edit", "auto"]),
                    background: try optionalString("background", allowed: ["auto", "opaque", "transparent"]),
                    inputFidelity: try optionalString("inputFidelity", allowed: ["low", "high"]),
                    inputImageMask: mask,
                    model: try optionalString("model"),
                    moderation: try optionalString("moderation", allowed: ["auto", "low"]),
                    outputCompression: try optionalInt("outputCompression", min: 0, max: 100),
                    outputFormat: try optionalString("outputFormat", allowed: ["png", "jpeg", "webp"]),
                    partialImages: try optionalInt("partialImages", min: 0, max: 3),
                    quality: try optionalString("quality", allowed: ["auto", "low", "medium", "high", "xhigh", "max"]),
                    size: size
                )

                return .success(value: args)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

private let imageGenerationInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false)
])

private let imageGenerationOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("result")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "result": .object(["type": .string("string")])
    ])
])

public let openaiImageGenerationOutputSchema = openAIToolSchema(imageGenerationOutputJSONSchema)

public let openaiImageGenerationToolFactory = createProviderExecutedToolFactory(
    id: "openai.image_generation",
    name: "image_generation",
    inputSchema: openAIToolSchema(imageGenerationInputJSONSchema),
    outputSchema: openaiImageGenerationOutputSchema
) { (args: OpenAIImageGenerationArgs) in
    var options = ProviderExecutedToolFactoryOptions()
    options.args = encodeOpenAIImageGenerationArgs(args)
    return options
}

private func encodeOpenAIImageGenerationArgs(_ args: OpenAIImageGenerationArgs) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [:]

    if let action = args.action { payload["action"] = .string(action) }
    if let background = args.background {
        payload["background"] = .string(background)
    }
    if let fidelity = args.inputFidelity {
        payload["inputFidelity"] = .string(fidelity)
    }
    if let mask = args.inputImageMask {
        var maskPayload: [String: JSONValue] = [:]
        if let fileId = mask.fileId {
            maskPayload["fileId"] = .string(fileId)
        }
        if let imageUrl = mask.imageUrl {
            maskPayload["imageUrl"] = .string(imageUrl)
        }
        payload["inputImageMask"] = .object(maskPayload)
    }
    if let model = args.model {
        payload["model"] = .string(model)
    }
    if let moderation = args.moderation {
        payload["moderation"] = .string(moderation)
    }
    if let compression = args.outputCompression {
        payload["outputCompression"] = .number(Double(compression))
    }
    if let format = args.outputFormat {
        payload["outputFormat"] = .string(format)
    }
    if let partial = args.partialImages {
        payload["partialImages"] = .number(Double(partial))
    }
    if let quality = args.quality {
        payload["quality"] = .string(quality)
    }
    if let size = args.size {
        payload["size"] = .string(size)
    }

    return payload
}
