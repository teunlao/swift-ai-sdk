import Foundation
import AISDKProvider

/// Validates provider-specific options against a schema.
///
/// Port of `@ai-sdk/provider-utils/src/parse-provider-options.ts`.
public func parseProviderOptions<Options>(
    provider: String,
    providerOptions: SharedV3ProviderOptions?,
    schema: FlexibleSchema<Options>
) async throws -> Options? {
    guard let providerOptions, let rawOptions = providerOptions[provider] else {
        return nil
    }

    let normalized = rawOptions.reduce(into: [String: Any]()) { result, entry in
        result[entry.key] = jsonValueToFoundation(entry.value)
    }

    let validation = await safeValidateTypes(
        ValidateTypesOptions(value: normalized, schema: schema)
    )

    switch validation {
    case .success(let value, _):
        return value
    case .failure(let error, _):
        throw InvalidArgumentError(
            argument: "providerOptions",
            message: "invalid \(provider) provider options",
            cause: error
        )
    }
}
