import Foundation
import AISDKProvider

/// Options for validating a value against a schema.
public struct ValidateTypesOptions<Output>: Sendable {
    public let value: AnySendable
    public let schema: FlexibleSchema<Output>
    /// What is being validated; it prefixes the error message.
    public let context: TypeValidationContext?

    public init(value: Any, schema: FlexibleSchema<Output>, context: TypeValidationContext? = nil) {
        self.value = AnySendable(value)
        self.schema = schema
        self.context = context
    }
}

/// Result of safe type validation, mirroring the TypeScript union.
public enum SafeValidateTypesResult<Output>: @unchecked Sendable {
    case success(value: Output, rawValue: Any)
    case failure(error: TypeValidationError, rawValue: Any)
}

/// Validates the value and throws `TypeValidationError` if validation fails.
///
/// Port of `@ai-sdk/provider-utils/src/validate-types.ts`
public func validateTypes<Output>(
    _ options: ValidateTypesOptions<Output>
) async throws -> Output {
    let result = await safeValidateTypes(options)

    switch result {
    case .success(let value, _):
        return value
    case .failure(let error, _):
        throw error
    }
}

/// Safely validates the value and returns the validation outcome.
///
/// Port of `@ai-sdk/provider-utils/src/validate-types.ts` (`safeValidateTypes`)
public func safeValidateTypes<Output>(
    _ options: ValidateTypesOptions<Output>
) async -> SafeValidateTypesResult<Output> {
    let schema = asSchema(options.schema)
    let rawValue = options.value.value
    let validation = await schema.validate(rawValue)

    switch validation {
    case .success(let typed):
        return .success(value: typed, rawValue: rawValue)
    case .failure(let error):
        guard let context = options.context else {
            return .failure(error: error, rawValue: rawValue)
        }
        // Schemas already wrap their failure without context; attach the context
        // to that failure's cause instead of nesting one validation error in another.
        let cause: any Error = error.context == nil ? (error.cause ?? error) : error
        return .failure(
            error: TypeValidationError.wrap(value: rawValue, cause: cause, context: context),
            rawValue: rawValue
        )
    }
}
