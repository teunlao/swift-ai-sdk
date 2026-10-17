import AISDKProvider

final class CacheControlValidator {
    private var breakpointCount = 0
    private var warnings: [SharedV4Warning] = []

    func getCacheControl(_ options: SharedV4ProviderMetadata?) -> JSONValue? {
        let fields = options?["alibaba"]
        var value = fields?["cacheControl"]
        if value == nil || value == .null { value = fields?["cache_control"] }
        guard let value else { return nil }
        switch value {
        case .null, .bool(false): return nil
        case .number(let number) where number == 0 || number.isNaN: return nil
        case .string(let string) where string.isEmpty: return nil
        default: break
        }
        breakpointCount += 1
        if breakpointCount > 4 {
            warnings.append(.other(message: "Max breakpoint limit exceeded. Only the last 4 cache markers will take effect."))
        }
        return value
    }
    func getWarnings() -> [SharedV4Warning] { warnings }
}
