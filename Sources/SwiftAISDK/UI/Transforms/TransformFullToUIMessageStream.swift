import Foundation
import AISDKProvider
import AISDKProviderUtils

public func transformFullToUIMessageStream(
    stream: AsyncThrowingStream<TextStreamPart, Error>,
    options: UIMessageTransformOptions = UIMessageTransformOptions()
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    toUIMessageStream(stream: stream, options: UIMessageStreamOptions<UIMessage>(
        messageMetadata: options.messageMetadata,
        sendReasoning: options.sendReasoning,
        sendSources: options.sendSources,
        sendFinish: options.sendFinish,
        sendStart: options.sendStart
    ))
}
