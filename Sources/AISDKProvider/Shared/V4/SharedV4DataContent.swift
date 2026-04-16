import Foundation

/**
 Binary content used by v4 file/skill upload interfaces.

 Swift adaptation of upstream byte-or-base64 unions.
 */
public enum SharedV4DataContent: Sendable, Equatable {
    case data(Data)
    case base64(String)
}
