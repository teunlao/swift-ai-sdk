import Foundation

/**
 Warning from the model.

 Port of `@ai-sdk/provider/src/shared/v3/shared-v3-warning.ts`.
 */
public enum SharedV3Warning: Sendable, Equatable, Codable {
    /// A feature is not supported by the model.
    case unsupported(feature: String, details: String?)

    /// A compatibility feature is used that might lead to suboptimal results.
    case compatibility(feature: String, details: String?)

    /// Other warning.
    case other(message: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case feature
        case details
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

        case let .other(message):
            try container.encode("other", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

