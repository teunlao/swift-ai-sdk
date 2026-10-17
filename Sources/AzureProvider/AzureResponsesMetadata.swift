import OpenAIProvider

public struct AzureResponsesProviderMetadata: Sendable, Equatable, Decodable {
    public var azure: ResponsesProviderMetadata
    public init(azure: ResponsesProviderMetadata) { self.azure = azure }
}

public struct AzureResponsesReasoningProviderMetadata: Sendable, Equatable, Decodable {
    public var azure: ResponsesReasoningProviderMetadata
    public init(azure: ResponsesReasoningProviderMetadata) { self.azure = azure }
}

public struct AzureResponsesTextProviderMetadata: Sendable, Equatable, Decodable {
    public var azure: ResponsesTextProviderMetadata
    public init(azure: ResponsesTextProviderMetadata) { self.azure = azure }
}

public struct AzureResponsesSourceDocumentProviderMetadata: Sendable, Equatable, Decodable {
    public var azure: ResponsesSourceDocumentProviderMetadata
    public init(azure: ResponsesSourceDocumentProviderMetadata) { self.azure = azure }
}
