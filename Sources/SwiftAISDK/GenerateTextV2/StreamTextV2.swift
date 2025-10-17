import Foundation
import AISDKProvider

// MARK: - Public API (Milestone 1)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    prompt: String
) throws -> DefaultStreamTextV2Result<OutputValue, PartialOutputValue> {
    // Resolve LanguageModel to a v3 model; for milestone 1 only v3 path is supported.
    let resolved: any LanguageModelV3 = try resolveLanguageModel(modelArg)

    let options = LanguageModelV3CallOptions(
        prompt: [
            .user(
                content: [.text(LanguageModelV3TextPart(text: prompt))],
                providerOptions: nil
            )
        ]
    )

    // Bridge provider async stream acquisition without blocking the caller.
    let (bridgeStream, continuation) = AsyncThrowingStream.makeStream(of: LanguageModelV3StreamPart.self)

    // Start producer task to fetch provider stream and forward its parts.
    Task {
        do {
            let providerResult = try await resolved.doStream(options: options)
            for try await part in providerResult.stream {
                continuation.yield(part)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    return DefaultStreamTextV2Result<OutputValue, PartialOutputValue>(
        baseModel: modelArg,
        model: resolved,
        providerStream: bridgeStream
    )
}

// MARK: - Result Type (Milestone 1)

public final class DefaultStreamTextV2Result<OutputValue: Sendable, PartialOutputValue: Sendable>: Sendable {
    public typealias Output = OutputValue
    public typealias PartialOutput = PartialOutputValue

    private let actor: StreamTextV2Actor

    init(
        baseModel: LanguageModel,
        model: any LanguageModelV3,
        providerStream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    ) {
        self.actor = StreamTextV2Actor(source: providerStream)
        _ = self.actor // keep strong reference
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        // Bridge async actor method into a non-async property via forwarding stream
        AsyncThrowingStream { continuation in
            Task {
                let inner = await actor.textStream()
                do {
                    for try await value in inner {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let inner = await actor.fullStream()
                do {
                    for try await value in inner {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Helpers (none needed for milestone 1)
