import Foundation

/**
 Reasoning output of a text generation. It contains a reasoning.

 Port of `@ai-sdk/ai/src/generate-text/reasoning-output.ts`.
 */
public struct ReasoningOutput: Sendable {
    /// Type discriminator.
    public let type: String = "reasoning"

    /// The reasoning text.
    public let text: String

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerMetadata: ProviderMetadata?

    public init(
        text: String,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.text = text
        self.providerMetadata = providerMetadata
    }
}
