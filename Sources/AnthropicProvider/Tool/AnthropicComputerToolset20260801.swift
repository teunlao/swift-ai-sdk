import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum AnthropicComputerToolsetMember: String, Codable, Sendable, CaseIterable {
    case screenshot
    case zoom
    case leftClick = "left_click"
    case rightClick = "right_click"
    case middleClick = "middle_click"
    case doubleClick = "double_click"
    case tripleClick = "triple_click"
    case leftClickDrag = "left_click_drag"
    case mouseMove = "mouse_move"
    case leftMouseDown = "left_mouse_down"
    case leftMouseUp = "left_mouse_up"
    case cursorPosition = "cursor_position"
    case scroll
    case type
    case key
    case holdKey = "hold_key"
    case wait
}

public struct AnthropicComputerToolsetArgs: Codable, Sendable, Equatable {
    public struct Configuration: Codable, Sendable, Equatable {
        public var enabled: Bool?
        public var deferLoading: Bool?

        public init(enabled: Bool? = nil, deferLoading: Bool? = nil) {
            self.enabled = enabled
            self.deferLoading = deferLoading
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = container.contains(.enabled) ? try container.decode(Bool.self, forKey: .enabled) : nil
            deferLoading = container.contains(.deferLoading) ? try container.decode(Bool.self, forKey: .deferLoading) : nil
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, deferLoading
        }
    }

    public var configs: [String: Configuration]?

    public init(configs: [String: Configuration]? = nil) {
        self.configs = configs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configs = container.contains(.configs) ? try container.decode([String: Configuration].self, forKey: .configs) : nil
        if let configs, let unknown = configs.keys.first(where: { AnthropicComputerToolsetMember(rawValue: $0) == nil }) {
            throw DecodingError.dataCorruptedError(forKey: .configs, in: container, debugDescription: "Unknown computer toolset member: \(unknown)")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case configs
    }
}

private let computerToolsetArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "configs": .object([
            "type": .string("object"),
            "properties": .object(Dictionary(uniqueKeysWithValues: AnthropicComputerToolsetMember.allCases.map { member in
                (member.rawValue, JSONValue.object([
                    "type": .string("object"),
                    "properties": .object([
                        "enabled": .object(["type": .string("boolean")]),
                        "deferLoading": .object(["type": .string("boolean")]),
                    ]),
                    "additionalProperties": .bool(false),
                ]))
            })),
            "additionalProperties": .bool(false),
        ]),
    ]),
    "additionalProperties": .bool(false),
])

public let anthropicComputerToolset20260801ArgsSchema = FlexibleSchema(
    Schema<AnthropicComputerToolsetArgs>.codable(AnthropicComputerToolsetArgs.self, jsonSchema: computerToolsetArgsJSONSchema)
)

private let computerToolsetInputSchema = FlexibleSchema(jsonSchema(.object([
    "type": .string("object"),
    "properties": .object([
        "action": .object([
            "type": .string("string"),
            "enum": .array(AnthropicComputerToolsetMember.allCases.map { .string($0.rawValue) }),
        ]),
        "coordinate": .object(["type": .string("array"), "items": .object(["type": .string("integer")]), "minItems": .number(2), "maxItems": .number(2)]),
        "duration": .object(["type": .string("number")]),
        "region": .object(["type": .string("array"), "items": .object(["type": .string("integer")]), "minItems": .number(4), "maxItems": .number(4)]),
        "repeat": .object(["type": .string("integer")]),
        "scroll_amount": .object(["type": .string("number")]),
        "scroll_direction": .object(["type": .string("string"), "enum": .array([.string("up"), .string("down"), .string("left"), .string("right")])]),
        "start_coordinate": .object(["type": .string("array"), "items": .object(["type": .string("integer")]), "minItems": .number(2), "maxItems": .number(2)]),
        "text": .object(["type": .string("string")]),
    ]),
    "required": .array([.string("action")]),
    "additionalProperties": .bool(false),
])))

private let computerToolsetFactory = createProviderDefinedToolFactory(
    id: "anthropic.computer_toolset_20260801",
    name: "computer",
    inputSchema: computerToolsetInputSchema
)

public func anthropicComputerToolset20260801(
    _ args: AnthropicComputerToolsetArgs = .init(),
    options: ProviderDefinedToolFactoryOptions = .init()
) -> Tool {
    var options = options
    if let configs = args.configs {
        options.args["configs"] = .object(configs.mapValues { config in
            var value: [String: JSONValue] = [:]
            if let enabled = config.enabled { value["enabled"] = .bool(enabled) }
            if let deferLoading = config.deferLoading { value["deferLoading"] = .bool(deferLoading) }
            return .object(value)
        })
    }
    return computerToolsetFactory(options)
}
