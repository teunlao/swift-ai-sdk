import Foundation

/**
 Data content accepted by v4 file/skill upload interfaces.

 Swift adaptation of upstream `SharedV4FileDataData | SharedV4FileDataText`.
 */
public enum SharedV4DataContent: Sendable, Equatable {
    case data(Data)
    case base64(String)
    case text(String)
}
