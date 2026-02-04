import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleTools: Sendable {
    public init() {}

    @discardableResult
    public func googleSearch(_ args: GoogleSearchArgs = .init()) -> Tool {
        googleSearchToolFactory(args)
    }

    /// Creates an Enterprise Web Search tool for grounding responses using a compliance-focused web index.
    /// Must have name `enterprise_web_search`.
    ///
    /// - Note: Only available on Vertex AI. Requires Gemini 2.0 or newer.
    @discardableResult
    public func enterpriseWebSearch() -> Tool {
        googleEnterpriseWebSearchTool()
    }

    /// Creates a Google Maps grounding tool that gives the model access to Google Maps data.
    /// Must have name `google_maps`.
    @discardableResult
    public func googleMaps() -> Tool {
        googleGoogleMapsTool()
    }

    @discardableResult
    public func urlContext() -> Tool {
        googleURLContextTool()
    }

    /// Enables Retrieval Augmented Generation (RAG) via the Gemini File Search tool.
    /// Must have name `file_search`.
    @discardableResult
    public func fileSearch(_ args: GoogleFileSearchArgs) -> Tool {
        googleFileSearchTool(args)
    }

    @discardableResult
    public func codeExecution() -> Tool {
        googleCodeExecutionTool()
    }

    /// Creates a Vertex RAG Store tool that enables the model to perform RAG searches against a Vertex RAG Store.
    /// Must have name `vertex_rag_store`.
    @discardableResult
    public func vertexRagStore(_ args: GoogleVertexRAGStoreArgs) -> Tool {
        googleVertexRAGStoreTool(args)
    }
}

public let googleTools = GoogleTools()
