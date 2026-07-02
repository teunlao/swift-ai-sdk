import Foundation
import AISDKProvider

/**
 Result of uploading a skill through the AI SDK.

 Port of `@ai-sdk/ai/src/upload-skill/upload-skill-result.ts`.
 */
public protocol UploadSkillResult: Sendable {
    var providerReference: ProviderReference { get }
    var displayTitle: String? { get }
    var name: String? { get }
    var description: String? { get }
    var latestVersion: String? { get }
    var providerMetadata: ProviderMetadata? { get }
    var warnings: [SharedV4Warning] { get }
}

public struct DefaultUploadSkillResult: UploadSkillResult, Equatable {
    public let providerReference: ProviderReference
    public let displayTitle: String?
    public let name: String?
    public let description: String?
    public let latestVersion: String?
    public let providerMetadata: ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: ProviderReference,
        displayTitle: String? = nil,
        name: String? = nil,
        description: String? = nil,
        latestVersion: String? = nil,
        providerMetadata: ProviderMetadata? = nil,
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
