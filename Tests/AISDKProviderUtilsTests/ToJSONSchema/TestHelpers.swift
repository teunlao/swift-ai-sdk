import Testing
@testable import AISDKProviderUtils
import AISDKProvider

enum SchemaTestHelpers {
    static func refs(_ options: PartialOptions? = nil) -> Refs {
        getRefs(options.map(Zod3Options.partial))
    }

    static func expect(
        _ actual: JsonSchemaObject?,
        equals expected: JsonSchemaObject?
    ) {
        switch (actual, expected) {
        case (.some(let lhs), .some(let rhs)):
            #expect(JSONValue.object(lhs) == JSONValue.object(rhs))
        case (nil, nil):
            break
        default:
            #expect(false, "Schema optionality mismatch")
        }
    }

    static func expect(
        _ actual: JsonSchemaObject,
        equals expected: JsonSchemaObject
    ) {
        #expect(JSONValue.object(actual) == JSONValue.object(expected))
    }
}
