import AISDKProvider
import AISDKProviderUtils

public enum OpenAIPromptCacheMode: String, Sendable, Equatable {
    case implicit
    case explicit
}

public enum OpenAIPromptCacheTTL: String, Sendable, Equatable {
    case thirtyMinutes = "30m"
}

public struct OpenAIPromptCacheOptions: Sendable, Equatable {
    public var mode: OpenAIPromptCacheMode?
    public var ttl: OpenAIPromptCacheTTL?

    public init(mode: OpenAIPromptCacheMode? = nil, ttl: OpenAIPromptCacheTTL? = nil) {
        self.mode = mode
        self.ttl = ttl
    }

    var jsonValue: JSONValue {
        var value: [String: JSONValue] = [:]
        if let mode {
            value["mode"] = .string(mode.rawValue)
        }
        if let ttl {
            value["ttl"] = .string(ttl.rawValue)
        }
        return .object(value)
    }
}

func parseOpenAIPromptCacheOptions(
    _ value: JSONValue?,
    vendor: String = "openai"
) throws -> OpenAIPromptCacheOptions? {
    guard let value, value != .null else {
        return nil
    }
    guard case .object(let object) = value else {
        throw TypeValidationError.wrap(
            value: value,
            cause: SchemaValidationIssuesError(vendor: vendor, issues: "promptCacheOptions must be an object")
        )
    }

    var result = OpenAIPromptCacheOptions()
    if let modeValue = object["mode"] {
        guard case .string(let rawMode) = modeValue,
              let mode = OpenAIPromptCacheMode(rawValue: rawMode) else {
            throw TypeValidationError.wrap(
                value: modeValue,
                cause: SchemaValidationIssuesError(vendor: vendor, issues: "promptCacheOptions.mode must be one of implicit, explicit")
            )
        }
        result.mode = mode
    }
    if let ttlValue = object["ttl"] {
        guard case .string(let rawTTL) = ttlValue,
              let ttl = OpenAIPromptCacheTTL(rawValue: rawTTL) else {
            throw TypeValidationError.wrap(
                value: ttlValue,
                cause: SchemaValidationIssuesError(vendor: vendor, issues: "promptCacheOptions.ttl must be 30m")
            )
        }
        result.ttl = ttl
    }

    return result
}

func openAIPromptCacheBreakpoint(
    from providerOptions: SharedV3ProviderOptions?,
    providerOptionsName: String = "openai"
) -> JSONValue? {
    guard case .object(let breakpoint)? = providerOptions?[providerOptionsName]?["promptCacheBreakpoint"],
          breakpoint["mode"] == .string("explicit") else {
        return nil
    }
    return .object(breakpoint)
}
