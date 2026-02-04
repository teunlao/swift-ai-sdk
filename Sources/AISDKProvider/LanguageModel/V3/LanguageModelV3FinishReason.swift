import Foundation

/**
 Reason why a language model finished generating a response.

 Contains both a unified finish reason and a raw finish reason from the provider.
 The unified finish reason is used to provide a consistent finish reason across different providers.
 The raw finish reason is used to provide the original finish reason from the provider.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3FinishReason = {
   unified:
     | 'stop'
     | 'length'
     | 'content-filter'
     | 'tool-calls'
     | 'error'
     | 'other';
   raw: string | undefined;
 };
 ```
 */
public struct LanguageModelV3FinishReason: Sendable, Codable, Equatable {
    /**
     Unified finish reason.

     This enables using the same finish reason across different providers.
     */
    public enum Unified: String, Sendable, Codable, Equatable {
        /// Model generated stop sequence.
        case stop

        /// Model generated maximum number of tokens.
        case length

        /// Content filter violation stopped the model.
        case contentFilter = "content-filter"

        /// Model triggered tool calls.
        case toolCalls = "tool-calls"

        /// Model stopped because of an error.
        case error

        /// Model stopped for other reasons.
        case other
    }

    /// Unified finish reason. This enables using the same finish reason across different providers.
    public let unified: Unified

    /// Raw finish reason from the provider. This is the original finish reason from the provider.
    public let raw: String?

    public init(unified: Unified, raw: String? = nil) {
        self.unified = unified
        self.raw = raw
    }
}

