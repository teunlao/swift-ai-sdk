import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Codable representation of OpenAI-compatible error payloads.
/// Mirrors `packages/openai-compatible/src/openai-compatible-error.ts`.
public struct OpenAICompatibleErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String?
        public let param: JSONValue?
        public let code: OpenAICompatibleErrorCode?

        public init(
            message: String,
            type: String? = nil,
            param: JSONValue? = nil,
            code: OpenAICompatibleErrorCode? = nil
        ) {
            self.message = message
            self.type = type
            self.param = param
            self.code = code
        }
    }

    public let error: ErrorPayload

    public init(error: ErrorPayload) {
        self.error = error
    }
}

/// Union type representing either a string or numeric error code.
public enum OpenAICompatibleErrorCode: Sendable, Equatable {
    case string(String)
    case number(Double)
}

extension OpenAICompatibleErrorCode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported OpenAI-compatible error code value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

struct OpenAICompatibleParsedStreamError: Sendable {
    let rawValue: JSONValue
    let message: String
}

private typealias OpenAICompatibleStreamErrorParser = @Sendable (
    AnySendable
) async -> SchemaValidationResult<OpenAICompatibleParsedStreamError>

/// Configuration describing how to parse provider error payloads.
public struct OpenAICompatibleErrorConfiguration: Sendable {
    public let failedResponseHandler: ResponseHandler<APICallError>
    private let extractMessage: @Sendable (JSONValue) throws -> String
    private let streamErrorParser: OpenAICompatibleStreamErrorParser

    public init(
        failedResponseHandler: @escaping ResponseHandler<APICallError>,
        extractMessage: @escaping @Sendable (JSONValue) throws -> String
    ) {
        self.failedResponseHandler = failedResponseHandler
        self.extractMessage = extractMessage
        self.streamErrorParser = { value in
            do {
                let rawValue = try jsonValue(from: value.value)
                return .success(value: OpenAICompatibleParsedStreamError(
                    rawValue: rawValue,
                    message: try extractMessage(rawValue)
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(
                    value: value.value,
                    cause: error
                ))
            }
        }
    }

    public init<ErrorData>(
        errorSchema: FlexibleSchema<ErrorData>,
        errorToMessage: @escaping @Sendable (ErrorData) -> String,
        extractMessage: @escaping @Sendable (JSONValue) throws -> String,
        isRetryable: (@Sendable (ProviderHTTPResponse, ErrorData?) -> Bool)? = nil
    ) {
        self.failedResponseHandler = createJsonErrorResponseHandler(
            errorSchema: errorSchema,
            errorToMessage: errorToMessage,
            isRetryable: isRetryable
        )
        self.extractMessage = extractMessage

        let schema = errorSchema.resolve()
        self.streamErrorParser = { value in
            switch await schema.validate(value.value) {
            case .success(let parsed):
                do {
                    return .success(value: OpenAICompatibleParsedStreamError(
                        rawValue: try jsonValue(from: value.value),
                        message: errorToMessage(parsed)
                    ))
                } catch {
                    return .failure(error: TypeValidationError.wrap(
                        value: value.value,
                        cause: error
                    ))
                }
            case .failure(let error):
                return .failure(error: error)
            }
        }
    }

    /// Extracts the provider error message from a JSON payload.
    /// - Parameter json: The JSON payload returned in a streaming error chunk.
    /// - Returns: The error message string, if it can be parsed.
    public func message(from json: JSONValue) -> String? {
        do {
            return try extractMessage(json)
        } catch {
            return nil
        }
    }

    func parseStreamError(_ value: Any) async -> SchemaValidationResult<OpenAICompatibleParsedStreamError> {
        await streamErrorParser(AnySendable(value))
    }
}

func createOpenAICompatibleStreamSchema<Data: Decodable & Sendable, Output>(
    dataType: Data.Type,
    errorConfiguration: OpenAICompatibleErrorConfiguration,
    transformData: @escaping @Sendable (Data) -> Output,
    transformError: @escaping @Sendable (OpenAICompatibleParsedStreamError) -> Output
) -> FlexibleSchema<Output> {
    let dataSchema = Schema<Data>.codable(
        dataType,
        jsonSchema: .object(["type": .string("object")])
    )

    return FlexibleSchema(Schema<Output>(
        jsonSchemaResolver: { .object(["type": .string("object")]) },
        validator: { value in
            switch await dataSchema.validate(value) {
            case .success(let data):
                return .success(value: transformData(data))
            case .failure:
                switch await errorConfiguration.parseStreamError(value) {
                case .success(let error):
                    return .success(value: transformError(error))
                case .failure(let error):
                    return .failure(error: error)
                }
            }
        }
    ))
}

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

private let openAICompatibleErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("message")]),
            "additionalProperties": .bool(true),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "type": .object(["type": .array([.string("string"), .string("null")])]),
                "param": .bool(true),
                "code": .object(["type": .array([.string("string"), .string("number"), .string("null")])])
            ])
        ])
    ])
])

public let openAICompatibleErrorDataSchema = FlexibleSchema(
    Schema<OpenAICompatibleErrorData>.codable(
        OpenAICompatibleErrorData.self,
        jsonSchema: openAICompatibleErrorJSONSchema
    )
)

private func defaultExtractMessage(from json: JSONValue) throws -> String {
    let data = try encoder.encode(json)
    let payload = try decoder.decode(OpenAICompatibleErrorData.self, from: data)
    return payload.error.message
}

public let defaultOpenAICompatibleErrorConfiguration = OpenAICompatibleErrorConfiguration(
    errorSchema: openAICompatibleErrorDataSchema,
    errorToMessage: { $0.error.message },
    extractMessage: defaultExtractMessage
)
