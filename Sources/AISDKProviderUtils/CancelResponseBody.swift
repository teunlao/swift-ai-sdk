import Foundation

/// Cancels a response body to release the underlying connection when possible.
public func cancelResponseBody(_ response: ProviderHTTPResponse) async {
    switch response.body {
    case .none, .data:
        return
    case .stream(let stream):
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            while true {
                guard (try await iterator.next()) != nil else {
                    break
                }
            }
        }

        task.cancel()
        _ = await task.result
    }
}
