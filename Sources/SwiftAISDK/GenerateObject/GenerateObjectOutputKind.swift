import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Output formats supported by `generateObject`/`streamObject`.

 Port of `@ai-sdk/ai/src/generate-object/generate-object.ts` output options.
 */
public enum GenerateObjectOutputKind: String, Sendable {
    case object = "object"
    case array = "array"
    case enumeration = "enum"
    case noSchema = "no-schema"
}
