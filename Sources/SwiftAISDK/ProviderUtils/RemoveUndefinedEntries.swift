import Foundation

/**
 Removes entries where the value is nil.
 Port of `@ai-sdk/provider-utils/src/remove-undefined-entries.ts`
 */
public func removeUndefinedEntries<T>(
    _ record: [String: T?]
) -> [String: T] {
    return Dictionary(
        uniqueKeysWithValues: record.compactMap { key, value in
            guard let value = value else { return nil }
            return (key, value)
        }
    )
}
