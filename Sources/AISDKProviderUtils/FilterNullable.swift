/**
 Type guard that checks whether a value is not nil.

 Swift adaptation of `@ai-sdk/provider-utils/src/is-non-nullable.ts`.
 */
public func isNonNullable<T>(_ value: T?) -> Bool {
    value != nil
}

/**
 Filters nil values out of a list of values.

 Swift adaptation of `@ai-sdk/provider-utils/src/filter-nullable.ts`.
 */
public func filterNullable<T>(_ values: T?...) -> [T] {
    values.compactMap { $0 }
}

/**
 Filters nil values out of an array of values.
 */
public func filterNullable<T>(_ values: [T?]) -> [T] {
    values.compactMap { $0 }
}
