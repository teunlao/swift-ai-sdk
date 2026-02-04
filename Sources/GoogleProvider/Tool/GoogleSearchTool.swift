import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleSearchArgs: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable {
        case modeDynamic = "MODE_DYNAMIC"
        case modeUnspecified = "MODE_UNSPECIFIED"
    }

    public var mode: Mode?
    public var dynamicThreshold: Double?

    public init(mode: Mode? = nil, dynamicThreshold: Double? = nil) {
        self.mode = mode
        self.dynamicThreshold = dynamicThreshold
    }
}

private let googleSearchInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string(GoogleSearchArgs.Mode.modeDynamic.rawValue),
                        .string(GoogleSearchArgs.Mode.modeUnspecified.rawValue)
                    ]),
                    "default": .string(GoogleSearchArgs.Mode.modeUnspecified.rawValue)
                ]),
                "dynamicThreshold": .object([
                    "type": .string("number"),
                    "default": .number(1)
                ])
            ])
        ])
    )
)

public let googleSearchToolFactory = createProviderToolFactory(
    id: "google.google_search",
    name: "google_search",
    inputSchema: googleSearchInputSchema,
    mapOptions: { (args: GoogleSearchArgs) in
        var payload = ProviderToolFactoryOptions(args: [:])

        // Apply defaults matching upstream (mode: MODE_UNSPECIFIED, dynamicThreshold: 1)
        let mode = args.mode ?? .modeUnspecified
        let threshold = args.dynamicThreshold ?? 1

        payload.args["mode"] = .string(mode.rawValue)
        payload.args["dynamicThreshold"] = .number(threshold)

        return payload
    }
)

@discardableResult
public func googleSearchTool(_ args: GoogleSearchArgs = .init()) -> Tool {
    googleSearchToolFactory(args)
}
