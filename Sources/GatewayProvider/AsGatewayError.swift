import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/as-gateway-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Upstream `GatewayErrorResponse` shape.
public struct GatewayErrorResponse: Decodable, Sendable {
    public let error: GatewayErrorBody
    public let generationId: String?

    public init(error: GatewayErrorBody, generationId: String? = nil) {
        self.error = error
        self.generationId = generationId
    }
}

/// Upstream `GatewayErrorResponse.error` shape.
public struct GatewayErrorBody: Decodable, Sendable {
    public let message: String
    public let type: String?
    public let param: JSONValue?
    public let code: JSONValue?

    public init(message: String, type: String? = nil, param: JSONValue? = nil, code: JSONValue? = nil) {
        self.message = message
        self.type = type
        self.param = param
        self.code = code
    }
}

func asGatewayError(_ error: Any?, authMethod: GatewayAuthMethod? = nil) -> GatewayError {
    if let gatewayError = error as? GatewayError {
        return gatewayError
    }

    // Timeout error detection (undici codes in upstream, URLError.timedOut in Swift).
    if isTimeoutError(error) {
        let originalMessage = (error as? Error)?.localizedDescription ?? "Unknown error"
        return GatewayTimeoutError.createTimeoutError(
            originalMessage: originalMessage,
            cause: error as? Error
        )
    }

    if let apiError = error as? APICallError {
        if let cause = apiError.cause, isTimeoutError(cause) {
            return GatewayTimeoutError.createTimeoutError(
                originalMessage: apiError.message,
                cause: apiError
            )
        }

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

private protocol ErrorCodeProviding {
    var code: String { get }
}

private func isTimeoutError(_ error: Any?) -> Bool {
    guard let error = error as? Error else {
        return false
    }

    // Swift runtime timeouts.
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return true
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue {
        return true
    }

    // Upstream checks undici-specific timeout codes to avoid false positives.
    let undiciTimeoutCodes: Set<String> = [
        "UND_ERR_HEADERS_TIMEOUT",
        "UND_ERR_BODY_TIMEOUT",
        "UND_ERR_CONNECT_TIMEOUT",
    ]

    if let coded = error as? ErrorCodeProviding {
        return undiciTimeoutCodes.contains(coded.code)
    }

    // Best-effort reflection for error types that expose a string `code` property.
    let mirror = Mirror(reflecting: error)
    if let child = mirror.children.first(where: { $0.label == "code" }),
       let code = child.value as? String {
        return undiciTimeoutCodes.contains(code)
    }

    return false
}

func createGatewayErrorFromResponse(
    response: Any?,
    statusCode: Int,
    defaultMessage: String = "Gateway request failed",
    cause: Error? = nil,
    authMethod: GatewayAuthMethod? = nil
) -> GatewayError {
    do {
        let decoded = try decodeGatewayErrorResponse(response)
        let message = decoded.error.message
        let errorType = decoded.error.type ?? "internal_server_error"
        let generationId = decoded.generationId

        switch errorType {
        case "authentication_error":
            return GatewayAuthenticationError.createContextualError(
                apiKeyProvided: authMethod == .apiKey,
                oidcTokenProvided: authMethod == .oidc,
                statusCode: statusCode,
                cause: cause,
                generationId: generationId
            )
        case "invalid_request_error":
            return GatewayInvalidRequestError(
                message: message,
                statusCode: statusCode,
                cause: cause,
                generationId: generationId
            )
        case "rate_limit_exceeded":
            return GatewayRateLimitError(
                message: message,
                statusCode: statusCode,
                cause: cause,
                generationId: generationId
            )
        case "model_not_found":
            let modelId = gatewayModelId(from: decoded.error.param)
            return GatewayModelNotFoundError(
                message: message,
                statusCode: statusCode,
                modelId: modelId,
                cause: cause,
                generationId: generationId
            )
        case "internal_server_error":
            fallthrough
        default:
            return GatewayInternalServerError(
                message: message,
                statusCode: statusCode,
                cause: cause,
                generationId: generationId
            )
        }
    } catch let validationError as TypeValidationError {
        return GatewayResponseError(
            message: "Invalid error response format: \(defaultMessage)",
            statusCode: statusCode,
            response: response,
            validationError: validationError,
            cause: cause,
            generationId: gatewayGenerationId(from: response)
        )
    } catch {
        let wrapped = TypeValidationError.wrap(value: response, cause: error)
        return GatewayResponseError(
            message: "Invalid error response format: \(defaultMessage)",
            statusCode: statusCode,
            response: response,
            validationError: wrapped,
            cause: cause,
            generationId: gatewayGenerationId(from: response)
        )
    }
}

private func gatewayGenerationId(from response: Any?) -> String? {
    guard let response else { return nil }

    if let dict = response as? [String: Any], let id = dict["generationId"] as? String {
        return id
    }

    if let json = response as? JSONValue,
       case .object(let dict) = json,
       case .string(let id)? = dict["generationId"] {
        return id
    }

    return nil
}

private func gatewayModelId(from param: JSONValue?) -> String? {
    guard case .object(let dict) = param else { return nil }
    guard case .string(let modelId)? = dict["modelId"] else { return nil }
    return modelId
}

private func decodeGatewayErrorResponse(_ response: Any?) throws -> GatewayErrorResponse {
    guard let response else {
        let serializationError = SchemaJSONSerializationError(value: NSNull())
        throw TypeValidationError.wrap(value: response, cause: serializationError)
    }

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
