import AISDKProvider
import AISDKProviderUtils

// Temporary bridge while generateText/streamText move from `experimentalContext` to tool context.
extension Optional where Wrapped == JSONValue {
    var legacyToolContext: Context? {
        if case .some(.object(let object)) = self { return object }
        return nil
    }
}
