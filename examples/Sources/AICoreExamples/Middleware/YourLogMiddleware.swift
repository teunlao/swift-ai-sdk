import ExamplesCore
import Foundation
import SwiftAISDK

let yourLogMiddleware: LanguageModelV3Middleware = LanguageModelV3Middleware(
  wrapGenerate: { doGenerate, _, params, _ in
    Logger.info("doGenerate called")
    Logger.info("prompt: \(encodeJSON(params.prompt) ?? "<unencodable>")")

    let result = try await doGenerate()

    Logger.info("doGenerate finished")
    Logger.info("generated content: \(String(describing: result.content))")
    return result
  },
  wrapStream: { _, doStream, params, _ in
    Logger.info("doStream called")
    Logger.info("prompt: \(encodeJSON(params.prompt) ?? "<unencodable>")")

    let result = try await doStream()
    var generatedText = ""

    let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
      let task = Task {
        do {
          for try await chunk in result.stream {
            if case .textDelta(_, let delta, _) = chunk {
              generatedText += delta
            }
            continuation.yield(chunk)
          }

          Logger.info("doStream finished")
          Logger.info("generated text: \(generatedText)")
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }

    return LanguageModelV3StreamResult(stream: stream, request: result.request, response: result.response)
  }
)

private func encodeJSON<T: Encodable>(_ value: T) -> String? {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  guard let data = try? encoder.encode(value) else { return nil }
  return String(data: data, encoding: .utf8)
}

