import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Encodes `UIMessageChunk` values into `JSONValue` payloads suitable for SSE.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-chunks.ts` (serialization utilities).
 */
func encodeUIMessageChunkToJSON(_ chunk: AnyUIMessageChunk) -> JSONValue {
    switch chunk {
    case .textStart(let id, let providerMetadata):
        return .object(baseObject([
            "type": .string("text-start"),
            "id": .string(id),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .textDelta(let id, let delta, let providerMetadata):
        return .object(baseObject([
            "type": .string("text-delta"),
            "id": .string(id),
            "delta": .string(delta),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .textEnd(let id, let providerMetadata, let citations):
        return .object(baseObject([
            "type": .string("text-end"),
            "id": .string(id),
            "providerMetadata": providerMetadataJSON(providerMetadata),
            "citations": citations.map { .array($0.map(citationJSON)) }
        ]))

    case .reasoningStart(let id, let providerMetadata):
        return .object(baseObject([
            "type": .string("reasoning-start"),
            "id": .string(id),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .reasoningDelta(let id, let delta, let providerMetadata):
        return .object(baseObject([
            "type": .string("reasoning-delta"),
            "id": .string(id),
            "delta": .string(delta),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .reasoningEnd(let id, let providerMetadata):
        return .object(baseObject([
            "type": .string("reasoning-end"),
            "id": .string(id),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .error(let errorText):
        return .object([
            "type": .string("error"),
            "errorText": .string(errorText)
        ])

    case .toolInputAvailable(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let title,
        let toolMetadata
    ):
        return .object(baseObject([
            "type": .string("tool-input-available"),
            "toolCallId": .string(toolCallId),
            "toolName": .string(toolName),
            "input": input,
            "providerExecuted": providerExecuted.map(JSONValue.bool),
            "providerMetadata": providerMetadataJSON(providerMetadata),
            "dynamic": dynamic.map(JSONValue.bool),
            "title": title.map(JSONValue.string),
            "toolMetadata": toolMetadata.map(JSONValue.object)
        ]))

    case .toolInputError(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let errorText,
        let title,
        let toolMetadata
    ):
        return .object(baseObject([
            "type": .string("tool-input-error"),
            "toolCallId": .string(toolCallId),
            "toolName": .string(toolName),
            "input": input,
            "providerExecuted": providerExecuted.map(JSONValue.bool),
            "providerMetadata": providerMetadataJSON(providerMetadata),
            "dynamic": dynamic.map(JSONValue.bool),
            "errorText": .string(errorText),
            "title": title.map(JSONValue.string),
            "toolMetadata": toolMetadata.map(JSONValue.object)
        ]))

    case .toolApprovalRequest(let approvalId, let toolCallId, let descriptor, let inputSchemaInput, let reason, let isAutomatic, let signature):
        return .object(baseObject([
            "type": .string("tool-approval-request"),
            "approvalId": .string(approvalId),
            "toolCallId": .string(toolCallId),
            "approvalDescriptor": descriptor,
            "inputSchemaInput": inputSchemaInput,
            "reason": reason.map(JSONValue.string),
            "isAutomatic": isAutomatic.map(JSONValue.bool),
            "signature": signature.map(JSONValue.string)
        ]))

    case .toolApprovalResponse(let approvalId, let approved, let reason, let providerExecuted, let providerMetadata):
        return .object(baseObject([
            "type": .string("tool-approval-response"),
            "approvalId": .string(approvalId),
            "approved": .bool(approved),
            "reason": reason.map(JSONValue.string),
            "providerExecuted": providerExecuted.map(JSONValue.bool),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .toolOutputAvailable(
        let toolCallId,
        let output,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let preliminary,
        let toolMetadata
    ):
        return .object(baseObject([
            "type": .string("tool-output-available"),
            "toolCallId": .string(toolCallId),
            "output": output,
            "providerExecuted": providerExecuted.map(JSONValue.bool),
            "providerMetadata": providerMetadataJSON(providerMetadata),
            "dynamic": dynamic.map(JSONValue.bool),
            "preliminary": preliminary.map(JSONValue.bool),
            "toolMetadata": toolMetadata.map(JSONValue.object)
        ]))

    case .toolOutputError(
        let toolCallId,
        let errorText,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let toolMetadata
    ):
        return .object(baseObject([
            "type": .string("tool-output-error"),
            "toolCallId": .string(toolCallId),
            "errorText": .string(errorText),
            "providerExecuted": providerExecuted.map(JSONValue.bool),
            "providerMetadata": providerMetadataJSON(providerMetadata),
            "dynamic": dynamic.map(JSONValue.bool),
            "toolMetadata": toolMetadata.map(JSONValue.object)
        ]))

    case .toolOutputDenied(let toolCallId):
        return .object([
            "type": .string("tool-output-denied"),
            "toolCallId": .string(toolCallId)
        ])

    case .toolInputStart(let toolCallId, let toolName, let providerExecuted, let providerMetadata, let dynamic, let title, let toolMetadata, let inputEncoding):
        return .object(baseObject([
            "type": .string("tool-input-start"),
            "inputEncoding": inputEncoding.map { .string($0.rawValue) },
            "toolCallId": .string(toolCallId),
            "toolName": .string(toolName),
            "providerExecuted": providerExecuted.map(JSONValue.bool),
            "providerMetadata": providerMetadataJSON(providerMetadata),
            "dynamic": dynamic.map(JSONValue.bool),
            "title": title.map(JSONValue.string),
            "toolMetadata": toolMetadata.map(JSONValue.object)
        ]))

    case .toolInputDelta(let toolCallId, let inputTextDelta):
        return .object([
            "type": .string("tool-input-delta"),
            "toolCallId": .string(toolCallId),
            "inputTextDelta": .string(inputTextDelta)
        ])

    case .sourceUrl(let sourceId, let url, let title, let providerMetadata):
        return .object(baseObject([
            "type": .string("source-url"),
            "sourceId": .string(sourceId),
            "url": .string(url),
            "title": title.map(JSONValue.string),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .sourceDocument(let sourceId, let mediaType, let title, let filename, let providerMetadata):
        return .object(baseObject([
            "type": .string("source-document"),
            "sourceId": .string(sourceId),
            "mediaType": .string(mediaType),
            "title": .string(title),
            "filename": filename.map(JSONValue.string),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .file(let url, let mediaType, let providerMetadata):
        return .object(baseObject([
            "type": .string("file"),
            "url": .string(url),
            "mediaType": .string(mediaType),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .custom(let kind, let providerMetadata):
        return .object(baseObject([
            "type": .string("custom"), "kind": .string(kind),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .reasoningFile(let url, let mediaType, let providerMetadata):
        return .object(baseObject([
            "type": .string("reasoning-file"), "url": .string(url), "mediaType": .string(mediaType),
            "providerMetadata": providerMetadataJSON(providerMetadata)
        ]))

    case .resetStep:
        return .object(["type": .string("reset-step")])

    case .data(let dataChunk):
        return .object(baseObject([
            "type": .string(dataChunk.typeIdentifier),
            "id": dataChunk.id.map(JSONValue.string),
            "data": dataChunk.data,
            "transient": dataChunk.transient.map(JSONValue.bool)
        ]))

    case .startStep:
        return .object(["type": .string("start-step")])

    case .finishStep:
        return .object(["type": .string("finish-step")])

    case .start(let messageId, let messageMetadata):
        return .object(baseObject([
            "type": .string("start"),
            "messageId": messageId.map(JSONValue.string),
            "messageMetadata": messageMetadata
        ]))

    case .finish(let finishReason, let messageMetadata):
        return .object(baseObject([
            "type": .string("finish"),
            "finishReason": finishReason.map { JSONValue.string($0.rawValue) },
            "messageMetadata": messageMetadata
        ]))

    case .abort(let reason):
        return .object(baseObject([
            "type": .string("abort"),
            "reason": reason.map(JSONValue.string)
        ]))

    case .messageMetadata(let metadata):
        return .object([
            "type": .string("message-metadata"),
            "messageMetadata": metadata
        ])
    }
}

private func citationJSON(_ citation: Citation) -> JSONValue {
    var source: [String: JSONValue?]
    switch citation.source {
    case .url(let id, let url, let title, let metadata):
        source = ["type": .string("source"), "sourceType": .string("url"), "id": .string(id),
                  "url": .string(url), "title": title.map(JSONValue.string),
                  "providerMetadata": providerMetadataJSON(metadata)]
    case .document(let id, let mediaType, let title, let filename, let metadata):
        source = ["type": .string("source"), "sourceType": .string("document"), "id": .string(id),
                  "mediaType": .string(mediaType), "title": .string(title),
                  "filename": filename.map(JSONValue.string), "providerMetadata": providerMetadataJSON(metadata)]
    }
    return .object(baseObject([
        "source": .object(baseObject(source)),
        "startIndex": citation.startIndex.map(JSONValue.number),
        "endIndex": citation.endIndex.map(JSONValue.number),
        "citedText": citation.citedText.map(JSONValue.string)
    ]))
}

private func providerMetadataJSON(
    _ metadata: ProviderMetadata?
) -> JSONValue? {
    guard let metadata else {
        return nil
    }

    let converted = metadata.mapValues { JSONValue.object($0) }
    return .object(converted)
}

private func baseObject(_ values: [String: JSONValue?]) -> [String: JSONValue] {
    values.compactMapValues { $0 }
}
