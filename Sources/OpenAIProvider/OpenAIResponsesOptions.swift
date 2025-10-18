import Foundation
import AISDKProvider
import AISDKProviderUtils

public let TOP_LOGPROBS_MAX = 20

public let openAIResponsesReasoningModelIds: [OpenAIResponsesModelId] = [
    "o1",
    "o1-2024-12-17",
    "o3-mini",
    "o3-mini-2025-01-31",
    "o3",
    "o3-2025-04-16",
    "o4-mini",
    "o4-mini-2025-04-16",
    "codex-mini-latest",
    "computer-use-preview",
    "gpt-5",
    "gpt-5-2025-08-07",
    "gpt-5-codex",
    "gpt-5-mini",
    "gpt-5-mini-2025-08-07",
    "gpt-5-nano",
    "gpt-5-nano-2025-08-07",
    "gpt-5-pro",
    "gpt-5-pro-2025-10-06"
].map(OpenAIResponsesModelId.init(rawValue:))

public let openAIResponsesModelIds: [OpenAIResponsesModelId] = (
    [
        "gpt-4.1",
        "gpt-4.1-2025-04-14",
        "gpt-4.1-mini",
        "gpt-4.1-mini-2025-04-14",
        "gpt-4.1-nano",
        "gpt-4.1-nano-2025-04-14",
        "gpt-4o",
        "gpt-4o-2024-05-13",
        "gpt-4o-2024-08-06",
        "gpt-4o-2024-11-20",
        "gpt-4o-audio-preview",
        "gpt-4o-audio-preview-2024-10-01",
        "gpt-4o-audio-preview-2024-12-17",
        "gpt-4o-search-preview",
        "gpt-4o-search-preview-2025-03-11",
        "gpt-4o-mini-search-preview",
        "gpt-4o-mini-search-preview-2025-03-11",
        "gpt-4o-mini",
        "gpt-4o-mini-2024-07-18",
        "gpt-4-turbo",
        "gpt-4-turbo-2024-04-09",
        "gpt-4-turbo-preview",
        "gpt-4-0125-preview",
        "gpt-4-1106-preview",
        "gpt-4",
        "gpt-4-0613",
        "gpt-4.5-preview",
        "gpt-4.5-preview-2025-02-27",
        "gpt-3.5-turbo-0125",
        "gpt-3.5-turbo",
        "gpt-3.5-turbo-1106",
        "chatgpt-4o-latest",
        "gpt-5-chat-latest"
    ] + openAIResponsesReasoningModelIds.map { $0.rawValue }
).map(OpenAIResponsesModelId.init(rawValue:))

public enum OpenAIResponsesIncludeValue: String, CaseIterable, Sendable {
    case webSearchCallActionSources = "web_search_call.action.sources"
    case codeInterpreterCallOutputs = "code_interpreter_call.outputs"
    case computerCallOutputImageURL = "computer_call_output.output.image_url"
    case fileSearchCallResults = "file_search_call.results"
    case messageInputImageURL = "message.input_image.image_url"
    case messageOutputTextLogprobs = "message.output_text.logprobs"
    case reasoningEncryptedContent = "reasoning.encrypted_content"
}

public enum OpenAIResponsesLogprobsOption: Sendable, Equatable {
    case bool(Bool)
    case number(Int)
}

public struct OpenAIResponsesProviderOptions: Sendable, Equatable {
    public var include: [OpenAIResponsesIncludeValue]?
    public var instructions: String?
    public var logprobs: OpenAIResponsesLogprobsOption?
    public var maxToolCalls: Int?
    public var metadata: JSONValue?
    public var parallelToolCalls: Bool?
    public var previousResponseId: String?
    public var promptCacheKey: String?
    public var reasoningEffort: String?
    public var reasoningSummary: String?
    public var safetyIdentifier: String?
    public var serviceTier: String?
    public var store: Bool?
    public var strictJsonSchema: Bool?
    public var textVerbosity: String?
    public var user: String?

    public init(
        include: [OpenAIResponsesIncludeValue]? = nil,
        instructions: String? = nil,
        logprobs: OpenAIResponsesLogprobsOption? = nil,
        maxToolCalls: Int? = nil,
        metadata: JSONValue? = nil,
        parallelToolCalls: Bool? = nil,
        previousResponseId: String? = nil,
        promptCacheKey: String? = nil,
        reasoningEffort: String? = nil,
        reasoningSummary: String? = nil,
        safetyIdentifier: String? = nil,
        serviceTier: String? = nil,
        store: Bool? = nil,
        strictJsonSchema: Bool? = nil,
        textVerbosity: String? = nil,
        user: String? = nil
    ) {
        self.include = include
        self.instructions = instructions
        self.logprobs = logprobs
        self.maxToolCalls = maxToolCalls
        self.metadata = metadata
        self.parallelToolCalls = parallelToolCalls
        self.previousResponseId = previousResponseId
        self.promptCacheKey = promptCacheKey
        self.reasoningEffort = reasoningEffort
        self.reasoningSummary = reasoningSummary
        self.safetyIdentifier = safetyIdentifier
        self.serviceTier = serviceTier
        self.store = store
        self.strictJsonSchema = strictJsonSchema
        self.textVerbosity = textVerbosity
        self.user = user
    }
}

private let openAIResponsesProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "include": .object([
            "type": .array([.string("array"), .string("null")]),
            "items": .object([
                "type": .string("string"),
                "enum": .array(openAIResponsesProviderOptionIncludeValues.map { JSONValue.string($0.rawValue) })
            ])
        ]),
        "instructions": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "logprobs": .object([
            "type": .array([.string("boolean"), .string("number"), .string("null")])
        ]),
        "maxToolCalls": .object([
            "type": .array([.string("number"), .string("null")])
        ]),
        "metadata": .object([
            "type": .array([.string("object"), .string("array"), .string("string"), .string("number"), .string("boolean"), .string("null")])
        ]),
        "parallelToolCalls": .object([
            "type": .array([.string("boolean"), .string("null")])
        ]),
        "previousResponseId": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "promptCacheKey": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "reasoningEffort": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "reasoningSummary": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "safetyIdentifier": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "serviceTier": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "store": .object([
            "type": .array([.string("boolean"), .string("null")])
        ]),
        "strictJsonSchema": .object([
            "type": .array([.string("boolean"), .string("null")])
        ]),
        "textVerbosity": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "user": .object([
            "type": .array([.string("string"), .string("null")])
        ])
    ])
])

private let openAIResponsesProviderOptionIncludeValues: [OpenAIResponsesIncludeValue] = [.reasoningEncryptedContent, .fileSearchCallResults, .messageOutputTextLogprobs]

public let openAIResponsesProviderOptionsSchema = FlexibleSchema<OpenAIResponsesProviderOptions>(
    jsonSchema(openAIResponsesProviderOptionsJSONSchema, validate: { value in
        do {
            let json = try jsonValue(from: value)
            guard case .object(let dict) = json else {
                let error = TypeValidationError.wrap(
                    value: value,
                    cause: SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                )
                return .failure(error: error)
            }

            let options = try parseOpenAIResponsesProviderOptions(dict: dict)
            return .success(value: options)
        } catch let error as TypeValidationError {
            return .failure(error: error)
        } catch {
            let wrapped = TypeValidationError.wrap(value: value, cause: error)
            return .failure(error: wrapped)
        }
    })
)

private func parseOpenAIResponsesProviderOptions(dict: [String: JSONValue]) throws -> OpenAIResponsesProviderOptions {
    var options = OpenAIResponsesProviderOptions()

    if let includeValue = dict["include"], includeValue != .null {
        guard case .array(let includeArray) = includeValue else {
            throw TypeValidationError.wrap(value: includeValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "include must be an array"))
        }

        var include: [OpenAIResponsesIncludeValue] = []
        include.reserveCapacity(includeArray.count)
        for entry in includeArray {
            guard case .string(let raw) = entry,
                  let parsed = OpenAIResponsesIncludeValue(rawValue: raw),
                  openAIResponsesProviderOptionIncludeValues.contains(parsed) else {
                throw TypeValidationError.wrap(value: entry, cause: SchemaValidationIssuesError(vendor: "openai", issues: "invalid include value"))
            }
            include.append(parsed)
        }
        options.include = include
    }

    options.instructions = try parseOptionalString(dict, key: "instructions")
    options.maxToolCalls = try parseOptionalInt(dict, key: "maxToolCalls")
    if let metadataValue = dict["metadata"], metadataValue != .null {
        options.metadata = metadataValue
    }
    options.parallelToolCalls = try parseOptionalBool(dict, key: "parallelToolCalls")
    options.previousResponseId = try parseOptionalString(dict, key: "previousResponseId")
    options.promptCacheKey = try parseOptionalString(dict, key: "promptCacheKey")
    options.reasoningEffort = try parseOptionalString(dict, key: "reasoningEffort")
    options.reasoningSummary = try parseOptionalString(dict, key: "reasoningSummary")
    options.safetyIdentifier = try parseOptionalString(dict, key: "safetyIdentifier")
    if let serviceTierValue = dict["serviceTier"], serviceTierValue != .null {
        guard case .string(let serviceTier) = serviceTierValue else {
            throw TypeValidationError.wrap(value: serviceTierValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "serviceTier must be a string"))
        }
        let allowedServiceTiers = ["auto", "flex", "priority", "default"]
        guard allowedServiceTiers.contains(serviceTier) else {
            throw TypeValidationError.wrap(value: serviceTierValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "invalid serviceTier"))
        }
        options.serviceTier = serviceTier
    }
    options.store = try parseOptionalBool(dict, key: "store")
    options.strictJsonSchema = try parseOptionalBool(dict, key: "strictJsonSchema")
    if let verbosityValue = dict["textVerbosity"], verbosityValue != .null {
        guard case .string(let verbosity) = verbosityValue else {
            throw TypeValidationError.wrap(value: verbosityValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "textVerbosity must be a string"))
        }
        let allowedVerbosity = ["low", "medium", "high"]
        guard allowedVerbosity.contains(verbosity) else {
            throw TypeValidationError.wrap(value: verbosityValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "invalid textVerbosity"))
        }
        options.textVerbosity = verbosity
    }
    options.user = try parseOptionalString(dict, key: "user")

    if let logprobsValue = dict["logprobs"], logprobsValue != .null {
        switch logprobsValue {
        case .bool(let value):
            options.logprobs = .bool(value)
        case .number(let number):
            let intValue = Int(number)
            if Double(intValue) != number || intValue < 1 || intValue > TOP_LOGPROBS_MAX {
                throw TypeValidationError.wrap(value: logprobsValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be between 1 and 20"))
            }
            options.logprobs = .number(intValue)
        default:
            throw TypeValidationError.wrap(value: logprobsValue, cause: SchemaValidationIssuesError(vendor: "openai", issues: "logprobs must be boolean or number"))
        }
    }

    return options
}

private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let stringValue) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string"))
    }
    return stringValue
}

private func parseOptionalBool(_ dict: [String: JSONValue], key: String) throws -> Bool? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .bool(let boolValue) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a boolean"))
    }
    return boolValue
}

private func parseOptionalInt(_ dict: [String: JSONValue], key: String) throws -> Int? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .number(let number) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a number"))
    }
    let intValue = Int(number)
    if Double(intValue) != number {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be an integer"))
    }
    return intValue
}
