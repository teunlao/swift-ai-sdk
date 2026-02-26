import Foundation
import Testing
import AISDKProvider
@testable import GatewayProvider

@Suite("createGatewayErrorFromResponse")
struct CreateGatewayErrorFromResponseTests {
    @Test("authentication_error maps to GatewayAuthenticationError with contextual message")
    func authenticationError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Invalid API key",
                "type": "authentication_error",
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 401)
        #expect(GatewayAuthenticationError.isInstance(error))

        if let auth = error as? GatewayAuthenticationError {
            #expect(auth.statusCode == 401)
            #expect(auth.type == "authentication_error")
            #expect(auth.message.contains("No authentication provided"))
        }
    }

    @Test("invalid_request_error maps to GatewayInvalidRequestError")
    func invalidRequestError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Missing required parameter",
                "type": "invalid_request_error",
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 400)
        #expect(GatewayInvalidRequestError.isInstance(error))
        if let invalid = error as? GatewayInvalidRequestError {
            #expect(invalid.message == "Missing required parameter")
            #expect(invalid.statusCode == 400)
        }
    }

    @Test("rate_limit_exceeded maps to GatewayRateLimitError")
    func rateLimitError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Rate limit exceeded. Try again later.",
                "type": "rate_limit_exceeded",
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 429)
        #expect(GatewayRateLimitError.isInstance(error))
        if let rate = error as? GatewayRateLimitError {
            #expect(rate.message == "Rate limit exceeded. Try again later.")
            #expect(rate.statusCode == 429)
        }
    }

    @Test("model_not_found maps to GatewayModelNotFoundError and extracts modelId from param")
    func modelNotFoundExtractsModelId() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Model not available",
                "type": "model_not_found",
                "param": ["modelId": "gpt-4-turbo"],
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 404)
        #expect(GatewayModelNotFoundError.isInstance(error))
        if let notFound = error as? GatewayModelNotFoundError {
            #expect(notFound.message == "Model not available")
            #expect(notFound.modelId == "gpt-4-turbo")
            #expect(notFound.statusCode == 404)
        }
    }

    @Test("model_not_found returns GatewayModelNotFoundError with nil modelId for invalid param")
    func modelNotFoundInvalidParam() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Model not available",
                "type": "model_not_found",
                "param": ["invalidField": "value"],
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 404)
        #expect(GatewayModelNotFoundError.isInstance(error))
        if let notFound = error as? GatewayModelNotFoundError {
            #expect(notFound.modelId == nil)
        }
    }

    @Test("internal_server_error maps to GatewayInternalServerError")
    func internalServerError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Internal server error occurred",
                "type": "internal_server_error",
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 500)
        #expect(GatewayInternalServerError.isInstance(error))
        if let internalError = error as? GatewayInternalServerError {
            #expect(internalError.message == "Internal server error occurred")
            #expect(internalError.statusCode == 500)
        }
    }

    @Test("unknown error type maps to GatewayInternalServerError")
    func unknownErrorTypeMapsToInternalServerError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Unknown error occurred",
                "type": "unknown_error_type",
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 500)
        #expect(GatewayInternalServerError.isInstance(error))
    }

    @Test("null message fails schema validation and returns GatewayResponseError using defaultMessage")
    func nullMessageCreatesResponseError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": NSNull(),
                "type": "authentication_error",
            ],
        ]

        let error = createGatewayErrorFromResponse(
            response: response,
            statusCode: 401,
            defaultMessage: "Custom default message"
        )

        #expect(GatewayResponseError.isInstance(error))
        if let responseError = error as? GatewayResponseError {
            #expect(responseError.message == "Invalid error response format: Custom default message")
            #expect(responseError.validationError != nil)
        }
    }

    @Test("error type can be null; defaults to internal server error")
    func nullErrorTypeDefaultsToInternalServerError() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Some error",
                "type": NSNull(),
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 500)
        #expect(GatewayInternalServerError.isInstance(error))
    }

    @Test("cause is preserved in created error")
    func preservesCause() async throws {
        struct Dummy: Error {}

        let cause = Dummy()
        let response: [String: Any] = [
            "error": [
                "message": "Rate limit hit",
                "type": "rate_limit_exceeded",
            ],
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 429, cause: cause)
        if let rate = error as? GatewayRateLimitError {
            #expect(rate.cause != nil)
        } else {
            Issue.record("Expected GatewayRateLimitError")
        }
    }

    @Test("generationId is captured on success and appended to error.message")
    func generationIdSupport() async throws {
        let response: [String: Any] = [
            "error": [
                "message": "Internal server error",
                "type": "internal_server_error",
            ],
            "generationId": "gen_01ABC123XYZ",
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 500)
        #expect(GatewayInternalServerError.isInstance(error))

        if let internalError = error as? GatewayInternalServerError {
            #expect(internalError.generationId == "gen_01ABC123XYZ")
            #expect(internalError.message.contains("[gen_01ABC123XYZ]"))
        }
    }

    @Test("generationId is captured even when validation fails")
    func generationIdOnValidationFailure() async throws {
        let response: [String: Any] = [
            "invalidField": "value",
            "generationId": "gen_invalid",
        ]

        let error = createGatewayErrorFromResponse(response: response, statusCode: 500)
        #expect(GatewayResponseError.isInstance(error))
        if let responseError = error as? GatewayResponseError {
            #expect(responseError.generationId == "gen_invalid")
            #expect(responseError.message.contains("[gen_invalid]"))
        }
    }
}
