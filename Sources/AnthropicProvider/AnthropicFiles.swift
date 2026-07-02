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
    let filename: String?
    let mimeType: String?
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
        let fileData = try toData(options.data)

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
            headers: headers,
            body: PostBody(content: .data(multipart.data), values: nil),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: anthropicUploadFileResponseSchema),
            fetch: config.fetch
        ).value

        var anthropicMetadata: [String: JSONValue] = [
            "filename": .string(response.filename ?? options.filename ?? "blob"),
            "mimeType": .string(response.mimeType ?? options.mediaType),
            "sizeBytes": .number(Double(response.sizeBytes)),
            "createdAt": .string(response.createdAt)
        ]
        if let downloadable = response.downloadable {
            anthropicMetadata["downloadable"] = .bool(downloadable)
        }

        return FilesV4UploadFileResult(
            providerReference: ["anthropic": response.id],
            mediaType: response.mimeType ?? options.mediaType,
            filename: response.filename ?? options.filename,
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

    private func toData(_ content: SharedV4DataContent) throws -> Data {
        switch content {
        case .data(let data):
            return data
        case .base64(let string):
            return try convertBase64ToData(string)
        case .text(let text):
            return Data(text.utf8)
        }
    }
}
