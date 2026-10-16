import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ByteDanceConfig: Sendable {
    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

private struct ByteDanceErrorResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let message: String
        let code: String?
    }
    let error: Payload?
    let message: String?
}

let byteDanceFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<ByteDanceErrorResponse>.codable(
        ByteDanceErrorResponse.self, jsonSchema: .object(["type": .string("object")])
    )),
    errorToMessage: { $0.error?.message ?? $0.message ?? "Unknown error" }
)
