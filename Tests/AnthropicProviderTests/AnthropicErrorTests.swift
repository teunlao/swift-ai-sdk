import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

@Suite("Anthropic error handling")
struct AnthropicErrorTests {
    @Test("anthropicErrorDataSchema validates payload")
    func schemaValidatesPayload() async throws {
        let payload = AnthropicErrorData(
            type: "error",
            error: .init(type: "invalid_request_error", message: "Missing model")
        )

        let json = try JSONEncoder().encode(payload)
        let decoded = try await parseJSON(
            ParseJSONWithSchemaOptions(text: String(decoding: json, as: UTF8.self), schema: anthropicErrorDataSchema)
        )

        #expect(decoded == payload)
    }

    @Test("anthropicFailedResponseHandler maps message")
    func failedResponseHandlerMapsMessage() async throws {
        let body = """
        {"type":"error","error":{"type":"invalid_request_error","message":"Something went wrong"}}
        """
        .data(using: .utf8)!

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 400,
            httpVersion: nil,
            headerFields: ["content-type": "application/json"]
        )!
        let providerResponse = ProviderHTTPResponse(
            url: url,
            httpResponse: httpResponse,
            body: .data(body),
            statusText: "Bad Request"
        )

        let input = ResponseHandlerInput(
            url: url.absoluteString,
            requestBodyValues: nil,
            response: providerResponse
        )

        let result = try await anthropicFailedResponseHandler(input)
        let error = result.value

        #expect(error.message == "Something went wrong")
        #expect(error.statusCode == 400)
        #expect(error.data as? AnthropicErrorData == AnthropicErrorData(
            type: "error",
            error: .init(type: "invalid_request_error", message: "Something went wrong")
        ))
    }
}
