import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAISkillsConfig: Sendable {
    let provider: String
    let url: @Sendable (_ path: String) -> String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

private struct OpenAIUploadSkillResponse: Codable, Sendable, Equatable {
    let id: String
    let name: String?
    let description: String?
    let defaultVersion: String?
    let latestVersion: String?
    let createdAt: Double
    let updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case defaultVersion = "default_version"
        case latestVersion = "latest_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private let openAIUploadSkillResponseSchema = FlexibleSchema(
    Schema<OpenAIUploadSkillResponse>.codable(
        OpenAIUploadSkillResponse.self,
        jsonSchema: [
            "type": "object",
            "required": ["id", "created_at"],
            "properties": [
                "id": ["type": "string"],
                "name": ["type": ["string", "null"]],
                "description": ["type": ["string", "null"]],
                "default_version": ["type": ["string", "null"]],
                "latest_version": ["type": ["string", "null"]],
                "created_at": ["type": "number"],
                "updated_at": ["type": ["number", "null"]]
            ]
        ]
    )
)

public final class OpenAISkills: SkillsV4 {
    public let specificationVersion = "v4"

    public var provider: String {
        config.provider
    }

    private let config: OpenAISkillsConfig

    init(config: OpenAISkillsConfig) {
        self.config = config
    }

    public func uploadSkill(options: SkillsV4UploadSkillCallOptions) async throws -> SkillsV4UploadSkillResult {
        var warnings: [SharedV4Warning] = []
        if options.displayTitle != nil {
            warnings.append(.unsupported(feature: "displayTitle", details: nil))
        }

        var builder = MultipartFormDataBuilder()
        for file in options.files {
            builder.appendFile(
                name: "files[]",
                filename: file.path,
                contentType: nil,
                data: try convertInlineFileDataToData(file.data)
            )
        }

        let response = try await postToAPI(
            url: config.url("/skills"),
            headers: try config.headers().compactMapValues { $0 },
            body: PostBody(content: .multipartFormData(builder), values: nil),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIUploadSkillResponseSchema),
            fetch: config.fetch
        ).value

        var metadata: [String: JSONValue] = [
            "createdAt": .number(response.createdAt)
        ]
        if let defaultVersion = response.defaultVersion {
            metadata["defaultVersion"] = .string(defaultVersion)
        }
        if let updatedAt = response.updatedAt {
            metadata["updatedAt"] = .number(updatedAt)
        }

        return SkillsV4UploadSkillResult(
            providerReference: ["openai": response.id],
            name: response.name,
            description: response.description,
            latestVersion: response.latestVersion,
            providerMetadata: ["openai": metadata],
            warnings: warnings
        )
    }
}
