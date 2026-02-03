import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Anthropic computer use tool options.

 Port of `@ai-sdk/anthropic/src/tool/computer_20241022.ts` and `computer_20250124.ts`.
 */
public struct AnthropicComputerOptions: Sendable, Equatable {
    /// The width of the display being controlled by the model in pixels.
    public var displayWidthPx: Int

    /// The height of the display being controlled by the model in pixels.
    public var displayHeightPx: Int

    /// The display number to control (only relevant for X11 environments). If specified, the tool will be provided a display number in the tool definition.
    public var displayNumber: Int?

    /// Enable zoom action (computer_20251124 only). Default: nil (provider default).
    public var enableZoom: Bool?

    public init(
        displayWidthPx: Int,
        displayHeightPx: Int,
        displayNumber: Int? = nil,
        enableZoom: Bool? = nil
    ) {
        self.displayWidthPx = displayWidthPx
        self.displayHeightPx = displayHeightPx
        self.displayNumber = displayNumber
        self.enableZoom = enableZoom
    }
}

// MARK: - Computer 20241022

private let computer20241022InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("key"),
                        .string("type"),
                        .string("mouse_move"),
                        .string("left_click"),
                        .string("left_click_drag"),
                        .string("right_click"),
                        .string("middle_click"),
                        .string("double_click"),
                        .string("screenshot"),
                        .string("cursor_position")
                    ])
                ]),
                "coordinate": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")])
                ]),
                "text": .object([
                    "type": .array([.string("string"), .string("null")])
                ])
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(true)
        ])
    )
)

private func computer20241022Args(for options: AnthropicComputerOptions) -> [String: JSONValue] {
    var args: [String: JSONValue] = [
        "displayWidthPx": .number(Double(options.displayWidthPx)),
        "displayHeightPx": .number(Double(options.displayHeightPx))
    ]
    if let displayNumber = options.displayNumber {
        args["displayNumber"] = .number(Double(displayNumber))
    }
    return args
}

private let computer20241022Factory = createProviderToolFactory(
    id: "anthropic.computer_20241022",
    name: "computer",
    inputSchema: computer20241022InputSchema
)

/// Creates a computer use tool (version 20241022) that gives Claude direct access to computer environments.
///
/// Claude can interact with computer environments through the computer use tool, which provides
/// screenshot capabilities and mouse/keyboard control for autonomous desktop interaction.
///
/// Image results are supported.
///
/// Tool name must be `computer`.
///
/// - Parameter options: Configuration including display dimensions and optional display number
/// - Returns: A configured computer use tool
///
/// **Input Schema**:
/// - `action`: The action to perform. The available actions are:
///   - `key`: Press a key or key-combination on the keyboard.
///     - This supports xdotool's `key` syntax.
///     - Examples: "a", "Return", "alt+Tab", "ctrl+s", "Up", "KP_0" (for the numpad 0 key).
///   - `type`: Type a string of text on the keyboard.
///   - `cursor_position`: Get the current (x, y) pixel coordinate of the cursor on the screen.
///   - `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.
///   - `left_click`: Click the left mouse button.
///   - `left_click_drag`: Click and drag the cursor to a specified (x, y) pixel coordinate on the screen.
///   - `right_click`: Click the right mouse button.
///   - `middle_click`: Click the middle mouse button.
///   - `double_click`: Double-click the left mouse button.
///   - `screenshot`: Take a screenshot of the screen.
/// - `coordinate`: (x, y): The x (pixels from the left edge) and y (pixels from the top edge) coordinates to move the mouse to. Required only by `action=mouse_move` and `action=left_click_drag`.
/// - `text`: Required only by `action=type` and `action=key`.
///
/// Port of `@ai-sdk/anthropic/src/tool/computer_20241022.ts`.
@discardableResult
public func anthropicComputer20241022(_ options: AnthropicComputerOptions) -> Tool {
    computer20241022Factory(.init(args: computer20241022Args(for: options)))
}

// MARK: - Computer 20250124

private let computer20250124InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("key"),
                        .string("hold_key"),
                        .string("type"),
                        .string("cursor_position"),
                        .string("mouse_move"),
                        .string("left_mouse_down"),
                        .string("left_mouse_up"),
                        .string("left_click"),
                        .string("left_click_drag"),
                        .string("right_click"),
                        .string("middle_click"),
                        .string("double_click"),
                        .string("triple_click"),
                        .string("scroll"),
                        .string("wait"),
                        .string("screenshot")
                    ])
                ]),
                "coordinate": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2)
                ]),
                "duration": .object([
                    "type": .array([.string("number"), .string("null")])
                ]),
                "scroll_amount": .object([
                    "type": .array([.string("number"), .string("null")])
                ]),
                "scroll_direction": .object([
                    "type": .array([.string("string"), .string("null")]),
                    "enum": .array([.string("up"), .string("down"), .string("left"), .string("right")])
                ]),
                "start_coordinate": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2)
                ]),
                "text": .object([
                    "type": .array([.string("string"), .string("null")])
                ])
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(true)
        ])
    )
)

private func computer20250124Args(for options: AnthropicComputerOptions) -> [String: JSONValue] {
    var args: [String: JSONValue] = [
        "displayWidthPx": .number(Double(options.displayWidthPx)),
        "displayHeightPx": .number(Double(options.displayHeightPx))
    ]
    if let displayNumber = options.displayNumber {
        args["displayNumber"] = .number(Double(displayNumber))
    }
    return args
}

private let computer20250124Factory = createProviderToolFactory(
    id: "anthropic.computer_20250124",
    name: "computer",
    inputSchema: computer20250124InputSchema
)

/// Creates a computer use tool (version 20250124) that gives Claude direct access to computer environments.
///
/// Claude can interact with computer environments through the computer use tool, which provides
/// screenshot capabilities and mouse/keyboard control for autonomous desktop interaction.
///
/// Image results are supported.
///
/// Tool name must be `computer`.
///
/// - Parameter options: Configuration including display dimensions and optional display number
/// - Returns: A configured computer use tool
///
/// **Input Schema**:
/// - `action`: The action to perform. The available actions are:
///   - `key`: Press a key or key-combination on the keyboard.
///     - This supports xdotool's `key` syntax.
///     - Examples: "a", "Return", "alt+Tab", "ctrl+s", "Up", "KP_0" (for the numpad 0 key).
///   - `hold_key`: Hold down a key or multiple keys for a specified duration (in seconds). Supports the same syntax as `key`.
///   - `type`: Type a string of text on the keyboard.
///   - `cursor_position`: Get the current (x, y) pixel coordinate of the cursor on the screen.
///   - `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.
///   - `left_mouse_down`: Press the left mouse button.
///   - `left_mouse_up`: Release the left mouse button.
///   - `left_click`: Click the left mouse button at the specified (x, y) pixel coordinate on the screen. You can also include a key combination to hold down while clicking using the `text` parameter.
///   - `left_click_drag`: Click and drag the cursor from `start_coordinate` to a specified (x, y) pixel coordinate on the screen.
///   - `right_click`: Click the right mouse button at the specified (x, y) pixel coordinate on the screen.
///   - `middle_click`: Click the middle mouse button at the specified (x, y) pixel coordinate on the screen.
///   - `double_click`: Double-click the left mouse button at the specified (x, y) pixel coordinate on the screen.
///   - `triple_click`: Triple-click the left mouse button at the specified (x, y) pixel coordinate on the screen.
///   - `scroll`: Scroll the screen in a specified direction by a specified amount of clicks of the scroll wheel, at the specified (x, y) pixel coordinate. DO NOT use PageUp/PageDown to scroll.
///   - `wait`: Wait for a specified duration (in seconds).
///   - `screenshot`: Take a screenshot of the screen.
/// - `coordinate`: (x, y): The x (pixels from the left edge) and y (pixels from the top edge) coordinates to move the mouse to. Required only by `action=mouse_move` and `action=left_click_drag`.
/// - `duration`: The duration to hold the key down for. Required only by `action=hold_key` and `action=wait`.
/// - `scroll_amount`: The number of 'clicks' to scroll. Required only by `action=scroll`.
/// - `scroll_direction`: The direction to scroll the screen. Required only by `action=scroll`.
/// - `start_coordinate`: (x, y): The x (pixels from the left edge) and y (pixels from the top edge) coordinates to start the drag from. Required only by `action=left_click_drag`.
/// - `text`: Required only by `action=type`, `action=key`, and `action=hold_key`. Can also be used by click or scroll actions to hold down keys while clicking or scrolling.
///
/// Port of `@ai-sdk/anthropic/src/tool/computer_20250124.ts`.
@discardableResult
public func anthropicComputer20250124(_ options: AnthropicComputerOptions) -> Tool {
    computer20250124Factory(.init(args: computer20250124Args(for: options)))
}

// MARK: - Computer 20251124

private let computer20251124InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("key"),
                        .string("hold_key"),
                        .string("type"),
                        .string("cursor_position"),
                        .string("mouse_move"),
                        .string("left_mouse_down"),
                        .string("left_mouse_up"),
                        .string("left_click"),
                        .string("left_click_drag"),
                        .string("right_click"),
                        .string("middle_click"),
                        .string("double_click"),
                        .string("triple_click"),
                        .string("scroll"),
                        .string("wait"),
                        .string("screenshot"),
                        .string("zoom")
                    ])
                ]),
                "coordinate": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2)
                ]),
                "duration": .object([
                    "type": .array([.string("number"), .string("null")])
                ]),
                "region": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(4),
                    "maxItems": .number(4)
                ]),
                "scroll_amount": .object([
                    "type": .array([.string("number"), .string("null")])
                ]),
                "scroll_direction": .object([
                    "type": .array([.string("string"), .string("null")]),
                    "enum": .array([.string("up"), .string("down"), .string("left"), .string("right")])
                ]),
                "start_coordinate": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2)
                ]),
                "text": .object([
                    "type": .array([.string("string"), .string("null")])
                ])
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(true)
        ])
    )
)

private func computer20251124Args(for options: AnthropicComputerOptions) -> [String: JSONValue] {
    var args: [String: JSONValue] = [
        "displayWidthPx": .number(Double(options.displayWidthPx)),
        "displayHeightPx": .number(Double(options.displayHeightPx))
    ]
    if let displayNumber = options.displayNumber {
        args["displayNumber"] = .number(Double(displayNumber))
    }
    if let enableZoom = options.enableZoom {
        args["enableZoom"] = .bool(enableZoom)
    }
    return args
}

private let computer20251124Factory = createProviderToolFactory(
    id: "anthropic.computer_20251124",
    name: "computer",
    inputSchema: computer20251124InputSchema
)

/// Creates a computer use tool (version 20251124) that gives Claude direct access to computer environments.
///
/// Claude can interact with computer environments through the computer use tool, which provides screenshot
/// capabilities and mouse/keyboard control for autonomous desktop interaction.
///
/// This version adds the zoom action for detailed screen region inspection.
///
/// Image results are supported.
///
/// Tool name must be `computer`.
///
/// - Parameter options: Configuration including display dimensions, optional display number, and optional zoom enablement.
/// - Returns: A configured computer use tool
///
/// Port of `@ai-sdk/anthropic/src/tool/computer_20251124.ts`.
@discardableResult
public func anthropicComputer20251124(_ options: AnthropicComputerOptions) -> Tool {
    computer20251124Factory(.init(args: computer20251124Args(for: options)))
}
