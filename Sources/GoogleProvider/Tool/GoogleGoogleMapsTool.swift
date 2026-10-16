import Foundation
import AISDKProvider
import AISDKProviderUtils

private let googleGoogleMapsInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ])
    )
)

public let googleGoogleMapsToolFactory = createProviderExecutedToolFactory(
    id: "google.google_maps",
    name: "google_maps",
    inputSchema: googleGoogleMapsInputSchema,
    outputSchema: googleGoogleMapsInputSchema
)

@discardableResult
public func googleGoogleMapsTool() -> Tool {
    googleGoogleMapsToolFactory(ProviderExecutedToolFactoryOptions(args: [:]))
}

