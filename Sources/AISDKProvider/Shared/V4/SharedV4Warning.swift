import Foundation

/**
 Warning from the provider surface.

 Port of `@ai-sdk/provider/src/shared/v4/shared-v4-warning.ts`.
 */
public enum SharedV4Warning: Sendable, Equatable, Codable {
    /// A feature is not supported by the model.
    case unsupported(feature: String, details: String?)

    /// A compatibility feature is used that might lead to suboptimal results.
    case compatibility(feature: String, details: String?)

    /// A deprecated feature or option is being used.
    case deprecated(setting: String, message: String)

    /// Other warning.
    case other(message: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case feature
        case details
        case setting
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "unsupported":
            let feature = try container.decode(String.self, forKey: .feature)
            let details = try container.decodeIfPresent(String.self, forKey: .details)
            self = .unsupported(feature: feature, details: details)
        case "compatibility":
            let feature = try container.decode(String.self, forKey: .feature)
            let details = try container.decodeIfPresent(String.self, forKey: .details)
            self = .compatibility(feature: feature, details: details)
        case "deprecated":
            let setting = try container.decode(String.self, forKey: .setting)
            let message = try container.decode(String.self, forKey: .message)
            self = .deprecated(setting: setting, message: message)
        case "other":
            let message = try container.decode(String.self, forKey: .message)
            self = .other(message: message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown warning type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .unsupported(feature, details):
            try container.encode("unsupported", forKey: .type)
            try container.encode(feature, forKey: .feature)
            try container.encodeIfPresent(details, forKey: .details)
        case let .compatibility(feature, details):
            try container.encode("compatibility", forKey: .type)
            try container.encode(feature, forKey: .feature)
            try container.encodeIfPresent(details, forKey: .details)
        case let .deprecated(setting, message):
            try container.encode("deprecated", forKey: .type)
            try container.encode(setting, forKey: .setting)
            try container.encode(message, forKey: .message)
        case let .other(message):
            try container.encode("other", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
