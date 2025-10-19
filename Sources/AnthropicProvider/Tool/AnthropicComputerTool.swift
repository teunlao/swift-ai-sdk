import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum AnthropicComputerAction: String, Sendable {
    case key
    case type
    case mouseMove = "mouse_move"
    case leftClick = "left_click"
    case leftClickDrag = "left_click_drag"
    case rightClick = "right_click"
    case middleClick = "middle_click"
    case doubleClick = "double_click"
    case screenshot
    case cursorPosition = "cursor_position"
}

public struct AnthropicComputerOptions: Sendable, Equatable {
    public var displayWidthPx: Int
    public var displayHeightPx: Int
    public var displayNumber: Int?

    public init(displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int? = nil) {
        self.displayWidthPx = displayWidthPx
        self.displayHeightPx = displayHeightPx
        self.displayNumber = displayNumber
    }
}

private let anthropicComputerInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object(["type": .string("string")]),
                "coordinate": .object(["type": .array([.string("array"), .string("null")])]),
                "text": .object(["type": .array([.string("string"), .string("null")])])
            ]),
            "additionalProperties": .bool(true)
        ])
    )
)

private func anthropicComputerArgs(for options: AnthropicComputerOptions) -> [String: JSONValue] {
    var args: [String: JSONValue] = [
        "display_width_px": .number(Double(options.displayWidthPx)),
        "display_height_px": .number(Double(options.displayHeightPx))
    ]
    if let displayNumber = options.displayNumber {
        args["display_number"] = .number(Double(displayNumber))
    }
    return args
}

private let anthropicComputer20241022Factory = createProviderDefinedToolFactory(
    id: "anthropic.computer_20241022",
    name: "computer",
    inputSchema: anthropicComputerInputSchema
)

private let anthropicComputer20250124Factory = createProviderDefinedToolFactory(
    id: "anthropic.computer_20250124",
    name: "computer",
    inputSchema: anthropicComputerInputSchema
)

@discardableResult
public func anthropicComputer20241022(_ options: AnthropicComputerOptions) -> Tool {
    anthropicComputer20241022Factory(.init(args: anthropicComputerArgs(for: options)))
}

@discardableResult
public func anthropicComputer20250124(_ options: AnthropicComputerOptions) -> Tool {
    anthropicComputer20250124Factory(.init(args: anthropicComputerArgs(for: options)))
}
