import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/as-gateway-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct GatewayErrorResponse: Decodable, Sendable {
    let error: GatewayErrorBody
}

struct GatewayErrorBody: Decodable, Sendable {
    let message: String
    let type: String?
    let param: GatewayModelNotFoundParam?
    let code: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case type
        case param
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = (try? container.decode(String.self, forKey: .message)) ?? "Gateway request failed"
        type = try? container.decodeIfPresent(String.self, forKey: .type)

        if let nested = try? container.decodeIfPresent(GatewayModelNotFoundParam.self, forKey: .param) {
            param = nested
        } else {
            param = nil
        }

        if let stringValue = try? container.decodeIfPresent(String.self, forKey: .code) {
            code = stringValue
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .code) {
            code = String(intValue)
        } else if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .code) {
            code = String(doubleValue)
        } else {
            code = nil
        }
    }
}

struct GatewayModelNotFoundParam: Decodable, Sendable {
    let modelId: String?

    private enum CodingKeys: String, CodingKey {
        case modelId
    }

    init(modelId: String?) {
        self.modelId = modelId
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        } else if let single = try? decoder.singleValueContainer(),
                  let raw = try? single.decode(String.self) {
            modelId = raw
        } else {
            modelId = nil
        }
    }
}

func asGatewayError(_ error: Any?, authMethod: GatewayAuthMethod? = nil) -> GatewayError {
    if let gatewayError = error as? GatewayError {
        return gatewayError
    }

    if let apiError = error as? APICallError {
        return createGatewayErrorFromResponse(
            response: extractApiCallResponse(apiError),
            statusCode: apiError.statusCode ?? 500,
            defaultMessage: "Gateway request failed",
            cause: apiError,
            authMethod: authMethod
        )
    }

    let baseMessage: String
    if let error = error as? Error {
        baseMessage = "Gateway request failed: \(error.localizedDescription)"
    } else if let error = error {
        baseMessage = "Gateway request failed: \(String(describing: error))"
    } else {
        baseMessage = "Unknown Gateway error"
    }

    let underlying = error as? Error

    return createGatewayErrorFromResponse(
        response: [:],
        statusCode: 500,
        defaultMessage: baseMessage,
        cause: underlying,
        authMethod: authMethod
    )
}

func createGatewayErrorFromResponse(
    response: Any,
    statusCode: Int,
    defaultMessage: String = "Gateway request failed",
    cause: Error? = nil,
    authMethod: GatewayAuthMethod? = nil
) -> GatewayError {
    do {
        let decoded = try decodeGatewayErrorResponse(response)
        let message = decoded.error.message.isEmpty ? defaultMessage : decoded.error.message
        let errorType = decoded.error.type ?? "internal_server_error"

        switch errorType {
        case "authentication_error":
            return GatewayAuthenticationError.createContextualError(
                apiKeyProvided: authMethod == .apiKey,
                oidcTokenProvided: authMethod == .oidc,
                statusCode: statusCode,
                cause: cause
            )
        case "invalid_request_error":
            return GatewayInvalidRequestError(
                message: message,
                statusCode: statusCode,
                cause: cause
            )
        case "rate_limit_exceeded":
            return GatewayRateLimitError(
                message: message,
                statusCode: statusCode,
                cause: cause
            )
        case "model_not_found":
            return GatewayModelNotFoundError(
                message: message,
                statusCode: statusCode,
                modelId: decoded.error.param?.modelId,
                cause: cause
            )
        case "internal_server_error":
            fallthrough
        default:
            return GatewayInternalServerError(
                message: message,
                statusCode: statusCode,
                cause: cause
            )
        }
    } catch let validationError as TypeValidationError {
        return GatewayResponseError(
            message: "Invalid error response format: \(defaultMessage)",
            statusCode: statusCode,
            response: response,
            validationError: validationError,
            cause: cause
        )
    } catch {
        let wrapped = TypeValidationError.wrap(value: response, cause: error)
        return GatewayResponseError(
            message: "Invalid error response format: \(defaultMessage)",
            statusCode: statusCode,
            response: response,
            validationError: wrapped,
            cause: cause
        )
    }
}

private func decodeGatewayErrorResponse(_ response: Any) throws -> GatewayErrorResponse {
    guard JSONSerialization.isValidJSONObject(response) else {
        let serializationError = SchemaJSONSerializationError(value: response)
        throw TypeValidationError.wrap(value: response, cause: serializationError)
    }

    do {
        let data = try JSONSerialization.data(withJSONObject: response, options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(GatewayErrorResponse.self, from: data)
    } catch {
        throw TypeValidationError.wrap(value: response, cause: error)
    }
}
