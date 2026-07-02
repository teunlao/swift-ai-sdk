import Foundation

/**
 File payload for a v4 skill upload.

 Port of `SkillsV4File` from `@ai-sdk/provider/src/skills/v4/skills-v4-upload-skill-call-options.ts`.
 */
public struct SkillsV4File: Sendable, Equatable {
    public let path: String
    public let data: SharedV4DataContent

    public var content: SharedV4DataContent {
        data
    }

    public init(path: String, data: SharedV4DataContent) {
        self.path = path
        self.data = data
    }

    public init(path: String, content: SharedV4DataContent) {
        self.path = path
        self.data = content
    }
}

/**
 Options for uploading a skill via the skills interface.

 Port of `@ai-sdk/provider/src/skills/v4/skills-v4-upload-skill-call-options.ts`.
 */
public struct SkillsV4UploadSkillCallOptions: Sendable, Equatable {
    public let files: [SkillsV4File]
    public let displayTitle: String?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        files: [SkillsV4File],
        displayTitle: String? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.files = files
        self.displayTitle = displayTitle
        self.providerOptions = providerOptions
    }
}
