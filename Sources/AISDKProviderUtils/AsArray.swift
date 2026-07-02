/// Normalizes a nil or non-array value into an array.
public func asArray<T>(_ value: T?) -> [T] {
    guard let value else {
        return []
    }
    return [value]
}

/// Normalizes an optional array into an array.
public func asArray<T>(_ value: [T]?) -> [T] {
    value ?? []
}
