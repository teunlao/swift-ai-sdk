import Foundation
import AISDKProvider
import AISDKProviderUtils

struct AnthropicSkillsConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

public final class AnthropicSkills: SkillsV4 {
    public let specificationVersion = "v4"

    public var provider: String {
        config.provider
    }

    private let config: AnthropicSkillsConfig

    init(config: AnthropicSkillsConfig) {
        self.config = config
    }

    public func uploadSkill(options: SkillsV4UploadSkillCallOptions) async throws -> SkillsV4UploadSkillResult {
        var builder = MultipartFormDataBuilder()

        if let displayTitle = options.displayTitle {
            builder.appendField(name: "display_title", value: displayTitle)
        }

        for file in options.files {
            builder.appendFile(
                name: "files[]",
                filename: file.path,
                contentType: nil,
                data: try toData(file.data)
            )
        }

        let multipart = builder.build()
        let baseHeaders = try requestHeaders(
            extra: [
                "anthropic-beta": "skills-2025-10-02"
            ]
        )
        let postHeaders = combineHeaders(
            baseHeaders.mapValues { Optional($0) },
            [
                "Content-Type": multipart.contentType
            ]
        ).compactMapValues { $0 }

        let response = try await postToAPI(
            url: "\(config.baseURL)/skills",
            headers: postHeaders,
            body: PostBody(content: .data(multipart.data), values: nil),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: anthropicSkillResponseSchema),
            fetch: config.fetch
        ).value

        let versionMetadata: AnthropicSkillVersionResponse?
        if let latestVersion = response.latestVersion {
            versionMetadata = try await getFromAPI(
                url: "\(config.baseURL)/skills/\(response.id)/versions/\(latestVersion)",
                headers: baseHeaders,
                failedResponseHandler: anthropicFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: anthropicSkillVersionResponseSchema),
                fetch: config.fetch
            ).value
        } else {
            versionMetadata = nil
        }

        let resolvedName = versionMetadata?.name ?? response.name
        let resolvedDescription = versionMetadata?.description ?? response.description

        return SkillsV4UploadSkillResult(
            providerReference: ["anthropic": response.id],
            displayTitle: response.displayTitle,
            name: resolvedName,
            description: resolvedDescription,
            latestVersion: response.latestVersion,
            providerMetadata: [
                "anthropic": [
                    "source": .string(response.source),
                    "createdAt": .string(response.createdAt),
                    "updatedAt": .string(response.updatedAt)
                ]
            ],
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
