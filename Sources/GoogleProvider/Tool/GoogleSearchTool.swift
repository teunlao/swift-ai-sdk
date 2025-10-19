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
                    "type": .array([.string("string"), .string("null")]),
                    "enum": .array([
                        .string(GoogleSearchArgs.Mode.modeDynamic.rawValue),
                        .string(GoogleSearchArgs.Mode.modeUnspecified.rawValue)
                    ])
                ]),
                "dynamicThreshold": .object([
                    "type": .array([.string("number"), .string("null")])
                ])
            ])
        ])
    )
)

public let googleSearchToolFactory = createProviderDefinedToolFactory(
    id: "google.google_search",
    name: "google_search",
    inputSchema: googleSearchInputSchema,
    mapOptions: { (args: GoogleSearchArgs) in
        var payload = ProviderDefinedToolFactoryOptions(args: [:])

        if let mode = args.mode {
            payload.args["mode"] = .string(mode.rawValue)
        }

        if let threshold = args.dynamicThreshold {
            payload.args["dynamicThreshold"] = .number(threshold)
        }

        return payload
    }
)

@discardableResult
public func googleSearchTool(_ args: GoogleSearchArgs = .init()) -> Tool {
    googleSearchToolFactory(args)
}
