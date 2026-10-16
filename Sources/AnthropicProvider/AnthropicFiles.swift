import Foundation
import AISDKProvider
import AISDKProviderUtils

struct AnthropicFilesConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

private struct AnthropicUploadFileResponse: Codable, Sendable, Equatable {
    let id: String
    let type: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let createdAt: String
    let downloadable: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case filename
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
        case downloadable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        guard type == "file" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected file response")
        }
        filename = try container.decode(String.self, forKey: .filename)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        sizeBytes = try container.decode(Int.self, forKey: .sizeBytes)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        downloadable = try container.decodeIfPresent(Bool.self, forKey: .downloadable)
    }
}

private let anthropicUploadFileResponseSchema = FlexibleSchema(
    Schema<AnthropicUploadFileResponse>.codable(
        AnthropicUploadFileResponse.self,
        jsonSchema: [
            "type": "object",
            "required": ["id", "type", "filename", "mime_type", "size_bytes", "created_at"],
            "properties": [
                "id": ["type": "string"],
                "type": ["type": "string"],
                "filename": ["type": "string"],
                "mime_type": ["type": "string"],
                "size_bytes": ["type": "number"],
                "created_at": ["type": "string"],
                "downloadable": ["type": ["boolean", "null"]]
            ]
        ]
    )
)

public final class AnthropicFiles: FilesV4 {
    public let specificationVersion = "v4"

    public var provider: String {
        config.provider
    }

    private let config: AnthropicFilesConfig

    init(config: AnthropicFilesConfig) {
        self.config = config
    }

    public func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        let fileData = try convertInlineFileDataToData(options.data)

        var builder = MultipartFormDataBuilder()
        builder.appendFile(
            name: "file",
            filename: options.filename ?? "blob",
            contentType: options.mediaType,
            data: fileData
        )

        let multipart = builder.build()
        let headers = try requestHeaders(
            extra: [
                "anthropic-beta": "files-api-2025-04-14",
                "Content-Type": multipart.contentType
            ]
        )

        let response = try await postToAPI(
            url: "\(config.baseURL)/files",
            headers: combineHeaders(headers.mapValues { Optional($0) }, options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: PostBody(content: .data(multipart.data), values: nil),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: anthropicUploadFileResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        ).value

        var anthropicMetadata: [String: JSONValue] = [
            "filename": .string(response.filename),
            "mimeType": .string(response.mimeType),
            "sizeBytes": .number(Double(response.sizeBytes)),
            "createdAt": .string(response.createdAt)
        ]
        if let downloadable = response.downloadable {
            anthropicMetadata["downloadable"] = .bool(downloadable)
        }

        return FilesV4UploadFileResult(
            providerReference: ["anthropic": response.id],
            mediaType: response.mimeType,
            filename: response.filename,
            providerMetadata: ["anthropic": anthropicMetadata],
            warnings: []
        )
    }

    private func requestHeaders(extra: [String: String?]) throws -> [String: String] {
        combineHeaders(
            try config.headers(),
            extra
        ).compactMapValues { $0 }
    }
}
