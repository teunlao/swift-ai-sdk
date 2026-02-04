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
    public func enterpriseWebSearch() -> Tool {
        googleTools.enterpriseWebSearch()
    }

    @discardableResult
    public func googleMaps() -> Tool {
        googleTools.googleMaps()
    }

    @discardableResult
    public func urlContext() -> Tool {
        googleTools.urlContext()
    }

    @discardableResult
    public func fileSearch(_ args: GoogleFileSearchArgs) -> Tool {
        googleTools.fileSearch(args)
    }

    @discardableResult
    public func codeExecution() -> Tool {
        googleTools.codeExecution()
    }

    @discardableResult
    public func vertexRagStore(_ args: GoogleVertexRAGStoreArgs) -> Tool {
        googleTools.vertexRagStore(args)
    }
}

public let googleVertexTools = GoogleVertexTools()
