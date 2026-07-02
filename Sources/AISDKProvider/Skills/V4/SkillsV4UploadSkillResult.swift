import Foundation

/**
 Result of uploading a skill via the skills interface.

 Port of `@ai-sdk/provider/src/skills/v4/skills-v4-upload-skill-result.ts`.
 */
public struct SkillsV4UploadSkillResult: Sendable, Equatable {
    public let providerReference: SharedV4ProviderReference
    public let displayTitle: String?
    public let name: String?
    public let description: String?
    public let latestVersion: String?
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: SharedV4ProviderReference,
        displayTitle: String? = nil,
        name: String? = nil,
        description: String? = nil,
        latestVersion: String? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.providerReference = providerReference
        self.displayTitle = displayTitle
        self.name = name
        self.description = description
        self.latestVersion = latestVersion
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}
