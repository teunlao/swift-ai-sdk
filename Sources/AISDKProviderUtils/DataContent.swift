import Foundation

/**
 Data content representation mirroring `@ai-sdk/provider-utils`.
 */
public enum DataContent: Sendable {
    /// Base64-encoded string
    case string(String)
    /// Raw binary data
    case data(Data)
}

/// Union type for data content or URL inputs (matches upstream usage across packages).
public enum DataContentOrURL: Sendable, Equatable {
    case data(Data)
    case string(String)
    case url(URL)
}
