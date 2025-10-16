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

/**
 Mode for JSON-oriented generation when schemas are provided.

 Matches the upstream union `'auto' | 'json' | 'tool'`.
 */
public enum GenerateObjectJSONMode: String, Sendable {
    case auto
    case json
    case tool
}

/**
 Mode for enum generation. Upstream currently restricts this to `'json'`.
 */
public enum GenerateObjectEnumMode: String, Sendable {
    case json
}
