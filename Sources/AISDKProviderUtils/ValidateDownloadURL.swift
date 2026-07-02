import Foundation

/// Validates that a URL is safe to download from.
public func validateDownloadUrl(_ url: String) throws {
    guard let parsed = URL(string: url), let scheme = parsed.scheme else {
        throw DownloadError(url: url, message: "Invalid URL: \(url)")
    }

    if scheme == "data" {
        return
    }

    guard scheme == "http" || scheme == "https" else {
        throw DownloadError(
            url: url,
            message: "URL scheme must be http, https, or data, got \(scheme):"
        )
    }

    let hostname = (parsed.host ?? "")
        .lowercased()
        .trimmingTrailingDots()

    guard !hostname.isEmpty else {
        throw DownloadError(url: url, message: "URL must have a hostname")
    }

    if hostname == "localhost" ||
        hostname.hasSuffix(".local") ||
        hostname.hasSuffix(".localhost") {
        throw DownloadError(
            url: url,
            message: "URL with hostname \(hostname) is not allowed"
        )
    }

    if let ipv4 = parseIPv4Literal(hostname) {
        if isPrivateIPv4(ipv4) {
            throw DownloadError(
                url: url,
                message: "URL with IP address \(hostname) is not allowed"
            )
        }
        return
    }

    if hostname.contains(":") {
        if isPrivateIPv6(hostname) {
            throw DownloadError(
                url: url,
                message: "URL with IPv6 address \(hostname) is not allowed"
            )
        }
        return
    }
}

private func parseIPv4Literal(_ hostname: String) -> [Int]? {
    let parts = hostname.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(parts.count) else { return nil }

    var values: [UInt64] = []
    values.reserveCapacity(parts.count)

    for part in parts {
        guard let value = parseIPv4Component(String(part)) else {
            return nil
        }
        values.append(value)
    }

    let address: UInt64
    switch values.count {
    case 1:
        guard values[0] <= UInt64(UInt32.max) else { return nil }
        address = values[0]
    case 2:
        guard values[0] <= 0xff, values[1] <= 0x00ff_ffff else { return nil }
        address = (values[0] << 24) | values[1]
    case 3:
        guard values[0] <= 0xff, values[1] <= 0xff, values[2] <= 0xffff else { return nil }
        address = (values[0] << 24) | (values[1] << 16) | values[2]
    case 4:
        guard values.allSatisfy({ $0 <= 0xff }) else { return nil }
        address = (values[0] << 24) | (values[1] << 16) | (values[2] << 8) | values[3]
    default:
        return nil
    }

    return [
        Int((address >> 24) & 0xff),
        Int((address >> 16) & 0xff),
        Int((address >> 8) & 0xff),
        Int(address & 0xff),
    ]
}

private func parseIPv4Component(_ component: String) -> UInt64? {
    guard !component.isEmpty else { return nil }

    let lowercased = component.lowercased()
    let radix: Int
    let digits: Substring

    if lowercased.hasPrefix("0x") {
        radix = 16
        digits = lowercased.dropFirst(2)
    } else if lowercased.count > 1 && lowercased.hasPrefix("0") {
        radix = 8
        digits = lowercased.dropFirst()
    } else {
        radix = 10
        digits = Substring(lowercased)
    }

    guard !digits.isEmpty else { return 0 }
    return UInt64(digits, radix: radix)
}

private func isPrivateIPv4(_ parts: [Int]) -> Bool {
    guard parts.count == 4 else { return true }

    let a = parts[0]
    let b = parts[1]
    let c = parts[2]

    if a == 0 { return true }
    if a == 10 { return true }
    if a == 100 && (64...127).contains(b) { return true }
    if a == 127 { return true }
    if a == 169 && b == 254 { return true }
    if a == 172 && (16...31).contains(b) { return true }
    if a == 192 && b == 0 && c == 0 { return true }
    if a == 192 && b == 168 { return true }
    if a == 198 && (b == 18 || b == 19) { return true }
    if a >= 240 { return true }

    return false
}

private func parseIPv6(_ ip: String) -> [Int]? {
    let zoneStripped = ip
        .lowercased()
        .split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)[0]

    let halves = zoneStripped.split(separator: "::", maxSplits: 1, omittingEmptySubsequences: false)
    guard halves.count <= 2 else { return nil }

    func groups(from segment: Substring) -> [Int]? {
        if segment.isEmpty { return [] }

        let parts = segment.split(separator: ":", omittingEmptySubsequences: false)
        var groups: [Int] = []
        groups.reserveCapacity(parts.count)

        for (index, part) in parts.enumerated() {
            if part.contains(".") {
                guard index == parts.count - 1,
                      let ipv4 = parseIPv4Literal(String(part)) else {
                    return nil
                }
                groups.append((ipv4[0] << 8) | ipv4[1])
                groups.append((ipv4[2] << 8) | ipv4[3])
                continue
            }

            guard let value = Int(part, radix: 16), (0...0xffff).contains(value) else {
                return nil
            }
            groups.append(value)
        }

        return groups
    }

    guard let head = groups(from: halves[0]) else { return nil }

    if halves.count == 2 {
        guard let tail = groups(from: halves[1]) else { return nil }
        let fill = 8 - head.count - tail.count
        guard fill >= 0 else { return nil }
        return head + Array(repeating: 0, count: fill) + tail
    }

    return head.count == 8 ? head : nil
}

private func isPrivateIPv6(_ ip: String) -> Bool {
    guard let groups = parseIPv6(ip) else { return true }

    func topZero(_ count: Int) -> Bool {
        groups.prefix(count).allSatisfy { $0 == 0 }
    }

    if topZero(7) && (groups[7] == 0 || groups[7] == 1) { return true }
    if (groups[0] & 0xfe00) == 0xfc00 { return true }
    if (groups[0] & 0xffc0) == 0xfe80 { return true }
    if (groups[0] & 0xffc0) == 0xfec0 { return true }
    if (groups[0] & 0xff00) == 0xff00 { return true }

    let embedsIPv4 =
        topZero(6) ||
        (topZero(5) && groups[5] == 0xffff) ||
        (topZero(4) && groups[4] == 0xffff && groups[5] == 0) ||
        (groups[0] == 0x0064 &&
            groups[1] == 0xff9b &&
            groups[2] == 0 &&
            groups[3] == 0 &&
            groups[4] == 0 &&
            groups[5] == 0) ||
        (groups[0] == 0x0064 && groups[1] == 0xff9b && groups[2] == 0x0001)

    if embedsIPv4 {
        let embedded = [
            (groups[6] >> 8) & 0xff,
            groups[6] & 0xff,
            (groups[7] >> 8) & 0xff,
            groups[7] & 0xff,
        ]
        return isPrivateIPv4(embedded)
    }

    return false
}

private extension String {
    func trimmingTrailingDots() -> String {
        var value = self
        while value.last == "." {
            value.removeLast()
        }
        return value
    }
}
