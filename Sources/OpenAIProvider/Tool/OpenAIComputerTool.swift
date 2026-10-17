import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIComputerSafetyCheck: Codable, Sendable, Equatable {
    public let id: String
    public let code: String?
    public let message: String?

    public init(id: String, code: String? = nil, message: String? = nil) {
        self.id = id
        self.code = code
        self.message = message
    }

    var jsonValue: JSONValue {
        var value: [String: JSONValue] = ["id": .string(id)]
        value["code"] = code.map(JSONValue.string)
        value["message"] = message.map(JSONValue.string)
        return .object(value)
    }
}

public enum OpenAIComputerAction: Codable, Sendable, Equatable {
    public enum Button: String, Codable, Sendable { case left, right, wheel, back, forward }
    public struct Point: Codable, Sendable, Equatable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    case click(button: Button, x: Double, y: Double, keys: [String]? = nil)
    case doubleClick(x: Double, y: Double, keys: [String]? = nil)
    case drag(path: [Point], keys: [String]? = nil)
    case keypress(keys: [String])
    case move(x: Double, y: Double, keys: [String]? = nil)
    case screenshot
    case scroll(x: Double, y: Double, scrollX: Double, scrollY: Double, keys: [String]? = nil)
    case type(text: String)
    case wait

    private enum CodingKeys: String, CodingKey { case type, button, x, y, keys, path, scrollX, scrollY, text }

    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        switch try value.decode(String.self, forKey: .type) {
        case "click": self = .click(button: try value.decode(Button.self, forKey: .button), x: try value.decode(Double.self, forKey: .x), y: try value.decode(Double.self, forKey: .y), keys: try value.decodeIfPresent([String].self, forKey: .keys))
        case "double_click": self = .doubleClick(x: try value.decode(Double.self, forKey: .x), y: try value.decode(Double.self, forKey: .y), keys: try value.decodeIfPresent([String].self, forKey: .keys))
        case "drag": self = .drag(path: try value.decode([Point].self, forKey: .path), keys: try value.decodeIfPresent([String].self, forKey: .keys))
        case "keypress": self = .keypress(keys: try value.decode([String].self, forKey: .keys))
        case "move": self = .move(x: try value.decode(Double.self, forKey: .x), y: try value.decode(Double.self, forKey: .y), keys: try value.decodeIfPresent([String].self, forKey: .keys))
        case "screenshot": self = .screenshot
        case "scroll": self = .scroll(x: try value.decode(Double.self, forKey: .x), y: try value.decode(Double.self, forKey: .y), scrollX: try value.decode(Double.self, forKey: .scrollX), scrollY: try value.decode(Double.self, forKey: .scrollY), keys: try value.decodeIfPresent([String].self, forKey: .keys))
        case "type": self = .type(text: try value.decode(String.self, forKey: .text))
        case "wait": self = .wait
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: value, debugDescription: "Unknown computer action type")
        }
    }

    public func encode(to encoder: Encoder) throws { try jsonValue.encode(to: encoder) }

    var jsonValue: JSONValue {
        var value: [String: JSONValue]
        var keys: [String]?
        switch self {
        case let .click(button, x, y, modifiers):
            value = ["type": .string("click"), "button": .string(button.rawValue), "x": .number(x), "y": .number(y)]; keys = modifiers
        case let .doubleClick(x, y, modifiers):
            value = ["type": .string("double_click"), "x": .number(x), "y": .number(y)]; keys = modifiers
        case let .drag(path, modifiers):
            value = ["type": .string("drag"), "path": .array(path.map { .object(["x": .number($0.x), "y": .number($0.y)]) })]; keys = modifiers
        case .keypress(let modifiers): value = ["type": .string("keypress")]; keys = modifiers
        case let .move(x, y, modifiers):
            value = ["type": .string("move"), "x": .number(x), "y": .number(y)]; keys = modifiers
        case .screenshot: value = ["type": .string("screenshot")]
        case let .scroll(x, y, scrollX, scrollY, modifiers):
            value = ["type": .string("scroll"), "x": .number(x), "y": .number(y), "scrollX": .number(scrollX), "scrollY": .number(scrollY)]; keys = modifiers
        case .type(let text): value = ["type": .string("type"), "text": .string(text)]
        case .wait: value = ["type": .string("wait")]
        }
        value["keys"] = keys.map { .array($0.map(JSONValue.string)) }
        return .object(value)
    }

    var wireValue: JSONValue {
        guard case .object(var value) = jsonValue else { preconditionFailure() }
        if case .scroll = self {
            value["scroll_x"] = value.removeValue(forKey: "scrollX")
            value["scroll_y"] = value.removeValue(forKey: "scrollY")
        }
        return .object(value)
    }
}

public struct OpenAIComputerInput: Codable, Sendable, Equatable {
    public let actions: [OpenAIComputerAction]
    public let pendingSafetyChecks: [OpenAIComputerSafetyCheck]
    public let status: String

    public init(actions: [OpenAIComputerAction], pendingSafetyChecks: [OpenAIComputerSafetyCheck], status: String) {
        self.actions = actions
        self.pendingSafetyChecks = pendingSafetyChecks
        self.status = status
    }

    func wireCall(id: String?, callId: String) -> JSONValue {
        var value: [String: JSONValue] = [
            "type": .string("computer_call"), "call_id": .string(callId), "status": .string(status),
            "actions": .array(actions.map(\.wireValue)), "pending_safety_checks": .array(pendingSafetyChecks.map(\.jsonValue))
        ]
        value["id"] = id.map(JSONValue.string)
        return .object(value)
    }
}

private let computerStrings: JSONValue = .object(["type": .string("array"), "items": .object(["type": .string("string")])])
private let computerSafetySchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("id")]),
    "properties": .object(["id": .object(["type": .string("string")]), "code": .object(["type": .string("string")]), "message": .object(["type": .string("string")])])
])
private let computerActionSchema: JSONValue = {
    func variant(_ type: String, fields: [String: JSONValue] = [:], required: [String] = [], keys: Bool = false) -> JSONValue {
        var properties = fields
        properties["type"] = .object(["type": .string("string"), "enum": .array([.string(type)])])
        if keys { properties["keys"] = computerStrings }
        return .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "required": .array((["type"] + required).map(JSONValue.string)), "properties": .object(properties)
        ])
    }
    let point: [String: JSONValue] = ["x": .object(["type": .string("number")]), "y": .object(["type": .string("number")])]
    var click = point
    click["button"] = .object(["type": .string("string"), "enum": .array(["left", "right", "wheel", "back", "forward"].map(JSONValue.string))])
    var scroll = point
    scroll["scrollX"] = .object(["type": .string("number")]); scroll["scrollY"] = .object(["type": .string("number")])
    return .object(["oneOf": .array([
        variant("click", fields: click, required: ["button", "x", "y"], keys: true),
        variant("double_click", fields: point, required: ["x", "y"], keys: true),
        variant("drag", fields: ["path": .object(["type": .string("array"), "items": .object([
            "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("x"), .string("y")]), "properties": .object(point)
        ])])], required: ["path"], keys: true),
        variant("keypress", fields: ["keys": computerStrings], required: ["keys"]),
        variant("move", fields: point, required: ["x", "y"], keys: true), variant("screenshot"),
        variant("scroll", fields: scroll, required: ["x", "y", "scrollX", "scrollY"], keys: true),
        variant("type", fields: ["text": .object(["type": .string("string")])], required: ["text"]), variant("wait")
    ])])
}()
private let computerInputJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("actions"), .string("pendingSafetyChecks"), .string("status")]),
    "properties": .object([
        "actions": .object(["type": .string("array"), "items": computerActionSchema]),
        "pendingSafetyChecks": .object(["type": .string("array"), "items": computerSafetySchema]),
        "status": .object(["type": .string("string"), "enum": .array(["in_progress", "completed", "incomplete"].map(JSONValue.string))])
    ])
])
private let computerOutputJSONSchema: JSONValue = {
    let fields: [String: JSONValue] = [
        "type": .object(["type": .string("string"), "enum": .array([.string("computer_screenshot")])]),
        "imageUrl": .object(["type": .string("string")]), "fileId": .object(["type": .string("string")]),
        "detail": .object(["type": .string("string"), "enum": .array(["auto", "low", "high", "original"].map(JSONValue.string))])
    ]
    let variants: [JSONValue] = ["imageUrl", "fileId"].map { key in .object([
        "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string(key)]), "properties": .object(fields)
    ]) }
    return .object([
        "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("output")]), "properties": .object([
            "output": .object(["anyOf": .array(variants)]),
            "acknowledgedSafetyChecks": .object(["type": .string("array"), "items": computerSafetySchema])
        ])
    ])
}()

public let openaiComputerInputSchema = openAIToolSchema(OpenAIComputerInput.self, computerInputJSONSchema)
public let openaiComputerOutputSchema = openAIToolSchema(computerOutputJSONSchema)
public let openaiComputerTool = createProviderDefinedToolFactoryWithOutputSchema(
    id: "openai.computer", name: "computer", inputSchema: openAIToolSchema(computerInputJSONSchema), outputSchema: openaiComputerOutputSchema
)

func mapOpenAIComputerCallInput(_ item: [String: JSONValue]) -> JSONValue {
    let actions: [JSONValue]
    if case .array(let values)? = item["actions"] { actions = values }
    else if let action = item["action"], action != .null { actions = [action] }
    else { actions = [] }
    let mapped = actions.map { action -> JSONValue in
        guard case .object(var value) = action else { preconditionFailure() }
        if value["type"] == .string("scroll") {
            value["scrollX"] = value.removeValue(forKey: "scroll_x")
            value["scrollY"] = value.removeValue(forKey: "scroll_y")
        }
        if value["keys"] == .null { value.removeValue(forKey: "keys") }
        return .object(value)
    }
    let checks: [JSONValue]
    if case .array(let values)? = item["pending_safety_checks"] {
        checks = values.map { value in
            guard case .object(var value) = value else { preconditionFailure() }
            if value["code"] == .null { value.removeValue(forKey: "code") }
            if value["message"] == .null { value.removeValue(forKey: "message") }
            return .object(value)
        }
    } else { checks = [] }
    return .object(["actions": .array(mapped), "pendingSafetyChecks": .array(checks), "status": item["status"]!])
}

func computerOutputPayload(_ value: JSONValue, callId: String) -> JSONValue {
    guard case .object(let value) = value, case .object(let output)? = value["output"] else { preconditionFailure() }
    var screenshot: [String: JSONValue] = ["type": .string("computer_screenshot")]
    screenshot["image_url"] = output["imageUrl"]
    screenshot["file_id"] = output["fileId"]
    screenshot["detail"] = output["detail"]
    var payload: [String: JSONValue] = ["type": .string("computer_call_output"), "call_id": .string(callId), "output": .object(screenshot)]
    payload["acknowledged_safety_checks"] = value["acknowledgedSafetyChecks"]
    return .object(payload)
}
