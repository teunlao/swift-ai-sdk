import Foundation
import AISDKProvider
import AISDKProviderUtils

public func parseAndValidateObjectResultWithRepair<PartialValue, ResultValue, ElementStream>(
    text: String,
    strategy: GenerateObjectOutputStrategy<PartialValue, ResultValue, ElementStream>,
    repairText: RepairTextFunction?,
    context: GenerateObjectValidationContext
) async throws -> ResultValue {
    do {
        return try await parseAndValidateObjectResult(
            text: text,
            strategy: strategy,
            context: context
        )
    } catch {
        guard let repairText,
              let noObjectError = error as? NoObjectGeneratedError,
              let cause = noObjectError.cause else {
            throw error
        }

        let repairReason: RepairTextError?
        if let parseError = cause as? JSONParseError {
            repairReason = .parse(parseError)
        } else if let validationError = cause as? TypeValidationError {
            repairReason = .validation(validationError)
        } else {
            repairReason = nil
        }

        guard let repairReason else {
            throw error
        }

        let repaired = await repairText(
            RepairTextOptions(text: text, error: repairReason)
        )

        guard let repaired else {
            throw error
        }

        return try await parseAndValidateObjectResult(
            text: repaired,
            strategy: strategy,
            context: context
        )
    }
}

private func parseAndValidateObjectResult<PartialValue, ResultValue, ElementStream>(
    text: String,
    strategy: GenerateObjectOutputStrategy<PartialValue, ResultValue, ElementStream>,
    context: GenerateObjectValidationContext
) async throws -> ResultValue {
    switch await safeParseJSON(ParseJSONOptions(text: text)) {
    case .success(let value, _):
        let validation = await strategy.validateFinal(value, context)
        switch validation {
        case .success(let result):
            return result
        case .failure(let error):
            throw NoObjectGeneratedError(
                message: "No object generated: response did not match schema.",
                cause: error,
                text: text,
                response: context.response,
                usage: context.usage,
                finishReason: context.finishReason
            )
        }

    case .failure(let error, _):
        throw NoObjectGeneratedError(
            message: "No object generated: could not parse the response.",
            cause: error,
            text: text,
            response: context.response,
            usage: context.usage,
            finishReason: context.finishReason
        )
    }
}
