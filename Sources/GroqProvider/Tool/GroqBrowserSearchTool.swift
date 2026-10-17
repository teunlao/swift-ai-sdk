import AISDKProvider
import AISDKProviderUtils

private let browserSearchSchema = FlexibleSchema(Schema<JSONValue>(
    jsonSchemaResolver: { ["type": "object", "properties": [:], "additionalProperties": false] },
    validator: { raw in
        do {
            guard case .object = try jsonValue(from: raw) else {
                throw InvalidArgumentError(argument: "value", message: "Expected an object.")
            }
            return .success(value: .object([:]))
        } catch { return .failure(error: TypeValidationError.wrap(value: raw, cause: error)) }
    }
))

let groqBrowserSearchFactory = createProviderExecutedToolFactory(
    id: "groq.browser_search", name: "browser_search", inputSchema: browserSearchSchema, outputSchema: browserSearchSchema
)

public func browserSearch(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
    groqBrowserSearchFactory(options)
}
