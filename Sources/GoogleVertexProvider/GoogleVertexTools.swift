import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-tools.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GoogleVertexTools: Sendable {
    public init() {}

    @discardableResult
    public func googleSearch(_ args: GoogleSearchArgs = .init()) -> Tool {
        googleTools.googleSearch(args)
    }

    @discardableResult
    public func urlContext() -> Tool {
        googleTools.urlContext()
    }

    @discardableResult
    public func codeExecution() -> Tool {
        googleTools.codeExecution()
    }
}

public let googleVertexTools = GoogleVertexTools()
