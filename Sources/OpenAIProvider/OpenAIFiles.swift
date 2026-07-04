import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIFilesConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

public struct OpenAIFilesOptions: Sendable, Equatable {
    public var purpose: String?
    public var expiresAfter: Double?

    public init(purpose: String? = nil, expiresAfter: Double? = nil) {
        self.purpose = purpose
        self.expiresAfter = expiresAfter
    }
}

private let openAIFilesOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "purpose": .object(["type": .string("string")]),
        "expiresAfter": .object(["type": .string("number")])
    ]),
    "additionalProperties": .bool(true)
])

let openAIFilesOptionsSchema = FlexibleSchema<OpenAIFilesOptions>(
    Schema(
        jsonSchemaResolver: { openAIFilesOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAIFilesOptions(purpose: nil, expiresAfter: nil)

                if let purposeValue = dict["purpose"], purposeValue != .null {
                    guard case .string(let purpose) = purposeValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "purpose must be a string")
                        return .failure(error: TypeValidationError.wrap(value: purposeValue, cause: error))
                    }
                    options.purpose = purpose
                }

                if let expiresAfterValue = dict["expiresAfter"], expiresAfterValue != .null {
                    guard case .number(let expiresAfter) = expiresAfterValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "expiresAfter must be a number")
                        return .failure(error: TypeValidationError.wrap(value: expiresAfterValue, cause: error))
                    }
                    options.expiresAfter = expiresAfter
                }

                return .success(value: options)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct OpenAIUploadFileResponse: Codable, Sendable, Equatable {
    let id: String
    let object: String?
    let bytes: Int?
    let createdAt: Int?
    let filename: String?
    let purpose: String?
    let status: String?
    let expiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case bytes
        case createdAt = "created_at"
        case filename
        case purpose
        case status
        case expiresAt = "expires_at"
    }
}

private let openAIUploadFileResponseSchema = FlexibleSchema(
    Schema<OpenAIUploadFileResponse>.codable(
        OpenAIUploadFileResponse.self,
        jsonSchema: [
            "type": "object",
            "required": ["id"],
            "properties": [
                "id": ["type": "string"],
                "object": ["type": ["string", "null"]],
                "bytes": ["type": ["number", "null"]],
                "created_at": ["type": ["number", "null"]],
                "filename": ["type": ["string", "null"]],
                "purpose": ["type": ["string", "null"]],
                "status": ["type": ["string", "null"]],
                "expires_at": ["type": ["number", "null"]]
            ]
        ]
    )
)

public final class OpenAIFiles: FilesV4 {
    public let specificationVersion = "v4"

    public var provider: String {
        config.provider
    }

    private let config: OpenAIFilesConfig

    init(config: OpenAIFilesConfig) {
        self.config = config
    }

    public func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAIFilesOptionsSchema
        )
        let fileData = try convertInlineFileDataToData(options.data)

        var builder = MultipartFormDataBuilder()
        builder.appendFile(
            name: "file",
            filename: options.filename,
            contentType: options.mediaType,
            data: fileData
        )
        builder.appendField(name: "purpose", value: openAIOptions?.purpose ?? "assistants")
        if let expiresAfter = openAIOptions?.expiresAfter {
            builder.appendField(name: "expires_after", value: openAIFormValue(from: expiresAfter))
        }

        let multipart = builder.build()
        let headers = combineHeaders(
            try config.headers(),
            ["Content-Type": multipart.contentType]
        ).compactMapValues { $0 }

        let response = try await postToAPI(
            url: "\(config.baseURL)/files",
            headers: headers,
            body: PostBody(content: .data(multipart.data), values: nil),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIUploadFileResponseSchema),
            fetch: config.fetch
        ).value

        var metadata: [String: JSONValue] = [:]
        if let filename = response.filename {
            metadata["filename"] = .string(filename)
        }
        if let purpose = response.purpose {
            metadata["purpose"] = .string(purpose)
        }
        if let bytes = response.bytes {
            metadata["bytes"] = .number(Double(bytes))
        }
        if let createdAt = response.createdAt {
            metadata["createdAt"] = .number(Double(createdAt))
        }
        if let status = response.status {
            metadata["status"] = .string(status)
        }
        if let expiresAt = response.expiresAt {
            metadata["expiresAt"] = .number(Double(expiresAt))
        }

        return FilesV4UploadFileResult(
            providerReference: ["openai": response.id],
            mediaType: options.mediaType,
            filename: response.filename ?? options.filename,
            providerMetadata: ["openai": metadata],
            warnings: []
        )
    }
}

private func openAIFormValue(from number: Double) -> String {
    guard number.isFinite else {
        return String(number)
    }

    let whole = number.rounded(.towardZero)
    if number == whole, whole >= Double(Int64.min), whole <= Double(Int64.max) {
        return String(Int64(whole))
    }

    return String(number)
}
