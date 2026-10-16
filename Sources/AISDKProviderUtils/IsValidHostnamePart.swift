import Foundation

/**
 Checks whether a value is a valid ASCII hostname part: 1–63 letters, digits or
 hyphens, without a leading or trailing hyphen.

 Use it before inserting a resource name, region or location into a generated
 hostname: it rejects values such as `evil.example.com/#` that could change the
 request destination.

 Port of `@ai-sdk/provider-utils/src/is-valid-hostname-part.ts`.
 */
public func isValidHostnamePart(_ value: String) -> Bool {
    let scalars = value.unicodeScalars
    guard (1...63).contains(scalars.count),
          let first = scalars.first,
          let last = scalars.last,
          first != "-",
          last != "-" else {
        return false
    }

    return scalars.allSatisfy { scalar in
        scalar == "-" || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
