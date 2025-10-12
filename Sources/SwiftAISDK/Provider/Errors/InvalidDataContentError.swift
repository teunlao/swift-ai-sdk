import Foundation

/**
 Error thrown when invalid data content is provided.

 Port of `@ai-sdk/ai/src/prompt/invalid-data-content-error.ts`.

 Data content must be either:
 - A base64-encoded string
 - Data (Swift equivalent of Uint8Array/ArrayBuffer/Buffer)
 - A URL pointing to the data

 ## Example
 ```swift
 // Valid content
 let valid1 = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
 let valid2 = "iVBORw0KGgoAAAA..." // base64 string
 let valid3 = URL(string: "data:image/png;base64,iVBORw0KGgo...")

 // Invalid content - will throw InvalidDataContentError
 let invalid = 123 // wrong type
 ```
 */
public struct InvalidDataContentError: Error, AISDKError, Sendable {
    public static let errorDomain = "AI_InvalidDataContentError"
    public var name: String { Self.errorDomain }

    public let message: String
    public let content: String // description of invalid content
    public let cause: (any Error)?

    public init(content: Any, cause: (any Error)? = nil, message: String? = nil) {
        self.content = String(describing: content)
        self.cause = cause

        if let message = message {
            self.message = message
        } else {
            self.message = "Invalid data content. Expected a base64 string, Data, or URL, but got \(type(of: content))."
        }
    }

    public var errorDescription: String? {
        message
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": Self.errorDomain,
            "message": message,
            "content": content
        ]

        if let cause = cause {
            dict["cause"] = String(describing: cause)
        }

        return dict
    }

    /// Type guard to check if an error is an InvalidDataContentError
    public static func isInstance(_ error: any Error) -> Bool {
        return error is InvalidDataContentError
    }
}
