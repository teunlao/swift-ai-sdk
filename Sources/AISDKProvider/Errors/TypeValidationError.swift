import Foundation

/**
 Context describing where a type validation failed.

 Port of `TypeValidationContext` from `@ai-sdk/provider/src/errors/type-validation-error.ts`.
 */
public struct TypeValidationContext: Sendable, Equatable {
    /// Field path in dot notation, e.g. `message.metadata`.
    public let field: String?
    /// Entity name, e.g. a tool name.
    public let entityName: String?
    /// Entity identifier, e.g. a message or tool call id.
    public let entityId: String?

    public init(field: String? = nil, entityName: String? = nil, entityId: String? = nil) {
        self.field = field
        self.entityName = entityName
        self.entityId = entityId
    }
}

/**
 * Type validation failed.
 *
 * Swift port of TypeScript `TypeValidationError`.
 */
public struct TypeValidationError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_TypeValidationError"

    public let name = "AI_TypeValidationError"
    public let message: String
    public let cause: (any Error)?
    public let value: Any?
    public let context: TypeValidationContext?

    public init(value: Any?, cause: any Error, context: TypeValidationContext? = nil) {
        self.value = value
        self.cause = cause
        self.context = context

        var contextPrefix = "Type validation failed"
        if let field = context?.field, !field.isEmpty {
            contextPrefix += " for \(field)"
        }
        let entityName = context?.entityName.flatMap { $0.isEmpty ? nil : $0 }
        let entityId = context?.entityId.flatMap { $0.isEmpty ? nil : $0 }
        if entityName != nil || entityId != nil {
            var parts: [String] = []
            if let entityName {
                parts.append(entityName)
            }
            if let entityId {
                parts.append("id: \"\(entityId)\"")
            }
            contextPrefix += " (\(parts.joined(separator: ", ")))"
        }

        self.message = """
            \(contextPrefix): \
            Value: \(stringifyErrorValue(value)).
            Error message: \(getErrorMessage(cause))
            """
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }

    /**
     * Wraps an error into a TypeValidationError.
     * Returns `cause` unchanged when it is already a TypeValidationError for the
     * same value and context; otherwise creates a new TypeValidationError.
     */
    public static func wrap(
        value: Any?,
        cause: any Error,
        context: TypeValidationContext? = nil
    ) -> TypeValidationError {
        if let tvError = cause as? TypeValidationError,
           areValuesEqual(tvError.value, value),
           tvError.context?.field == context?.field,
           tvError.context?.entityName == context?.entityName,
           tvError.context?.entityId == context?.entityId {
            return tvError
        }

        return TypeValidationError(value: value, cause: cause, context: context)
    }

    private static func areValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let l), .some(let r)):
            if let l = l as? JSONValue, let r = r as? JSONValue {
                return l == r
            }
            return String(describing: l) == String(describing: r)
        default:
            return false
        }
    }
}
