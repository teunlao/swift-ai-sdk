import AISDKProvider

func convertSharedV4WarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        return .other(message: "\(setting): \(message)")
    case let .other(message):
        return .other(message: message)
    }
}
