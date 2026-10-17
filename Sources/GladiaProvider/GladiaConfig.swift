import Foundation
import AISDKProviderUtils

struct GladiaConfig: Sendable {
    let provider: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}
