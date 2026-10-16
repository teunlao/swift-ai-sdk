import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Functions that refine parsed tool inputs, keyed by tool name. The refined input
 is used for execution, outputs, callbacks and telemetry.

 Port of `@ai-sdk/ai/src/generate-text/tool-input-refinement.ts`.
 */
public typealias ToolInputRefinement = [String: @Sendable (JSONValue) async throws -> JSONValue]

/// An approved tool approval whose input failed revalidation.
struct InvalidToolApproval: Sendable {
    let approval: CollectedToolApproval
    let error: InvalidToolInputError
}

/**
 Revalidates approved tool approvals before their tools execute.

 Port of `@ai-sdk/ai/src/generate-text/validate-tool-approvals.ts`: the approved
 input must still satisfy the tool's input schema and survive input refinement
 unchanged; the current tool approval configuration may still deny the call.
 */
func validateApprovedToolApprovals(
    _ approvedToolApprovals: [CollectedToolApproval],
    tools: ToolSet?,
    toolApproval: ToolApprovalConfiguration?,
    messages: [ModelMessage],
    toolsContext: ToolsContext,
    runtimeContext: Context,
    refineToolInput: ToolInputRefinement?
) async throws -> (
    approved: [CollectedToolApproval],
    denied: [CollectedToolApproval],
    invalid: [InvalidToolApproval]
) {
    var approved: [CollectedToolApproval] = []
    var denied: [CollectedToolApproval] = []
    var invalid: [InvalidToolApproval] = []

    for approval in approvedToolApprovals {
        let toolCall = approval.toolCall
        let tool = tools?[toolCall.toolName]

        if let tool, tool.execute != nil {
            let schemaInput = approval.approvalRequest.inputSchemaInput ?? toolCall.input
            let validation = await safeValidateTypes(
                ValidateTypesOptions(value: jsonValueToFoundation(schemaInput), schema: tool.inputSchema)
            )

            var validationError: (any Error)?
            switch validation {
            case .failure(let error, _):
                validationError = error
            case .success(let value, _):
                do {
                    let revalidated = try await refineParsedToolCallInput(
                        toolCall.with(input: value),
                        refineToolInput: refineToolInput
                    )
                    if revalidated.input != toolCall.input {
                        validationError = ApprovedToolInputMismatchError()
                    }
                } catch {
                    validationError = error
                }
            }

            if let validationError {
                invalid.append(InvalidToolApproval(
                    approval: approval,
                    error: InvalidToolInputError(
                        toolName: toolCall.toolName,
                        toolInput: toolCall.input.jsonString,
                        cause: validationError
                    )
                ))
                continue
            }
        }

        let status = try await resolveToolApproval(
            tools: tools,
            toolCall: toolCall,
            toolApproval: toolApproval,
            messages: messages,
            toolsContext: toolsContext,
            runtimeContext: runtimeContext
        )

        if case .denied(let reason) = status {
            denied.append(approval.with(approvalResponse: ToolApprovalResponse(
                approvalId: approval.approvalResponse.approvalId,
                approved: false,
                reason: reason ?? approval.approvalResponse.reason,
                providerExecuted: approval.approvalResponse.providerExecuted
            )))
        } else {
            approved.append(approval)
        }
    }

    return (approved, denied, invalid)
}

private struct ApprovedToolInputMismatchError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Approved tool input does not match the validated schema output."
    }
}

extension JSONValue {
    /// Compact JSON text of the value (`JSON.stringify`).
    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
