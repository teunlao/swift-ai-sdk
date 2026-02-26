import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayTools")
struct GatewayToolsTests {
    @Test("parallelSearch tool factory produces provider tool with encoded args")
    func parallelSearchFactory() async throws {
        let tool = gatewayTools.parallelSearch()
        #expect(tool.type == .provider)
        #expect(tool.id == "gateway.parallel_search")
        #expect(tool.name == "parallel_search")
        #expect(tool.args == [:])
        #expect(tool.outputSchema != nil)

        let configured = gatewayTools.parallelSearch(.init(
            mode: .agentic,
            maxResults: 7,
            sourcePolicy: .init(
                includeDomains: ["wikipedia.org"],
                excludeDomains: ["reddit.com"],
                afterDate: "2024-01-01"
            ),
            excerpts: .init(maxCharsPerResult: 200, maxCharsTotal: 2000),
            fetchPolicy: .init(maxAgeSeconds: 0)
        ))

        guard let args = configured.args else {
            Issue.record("Expected args")
            return
        }

        #expect(args["mode"] == .string("agentic"))
        #expect(args["maxResults"] == .number(7))

        if case .object(let source)? = args["sourcePolicy"] {
            #expect(source["includeDomains"] == .array([.string("wikipedia.org")]))
            #expect(source["excludeDomains"] == .array([.string("reddit.com")]))
            #expect(source["afterDate"] == .string("2024-01-01"))
        } else {
            Issue.record("Expected sourcePolicy object")
        }

        if case .object(let excerpts)? = args["excerpts"] {
            #expect(excerpts["maxCharsPerResult"] == .number(200))
            #expect(excerpts["maxCharsTotal"] == .number(2000))
        } else {
            Issue.record("Expected excerpts object")
        }

        if case .object(let fetchPolicy)? = args["fetchPolicy"] {
            #expect(fetchPolicy["maxAgeSeconds"] == .number(0))
        } else {
            Issue.record("Expected fetchPolicy object")
        }
    }

    @Test("perplexitySearch tool factory produces provider tool with encoded args")
    func perplexitySearchFactory() async throws {
        let tool = gatewayTools.perplexitySearch()
        #expect(tool.type == .provider)
        #expect(tool.id == "gateway.perplexity_search")
        #expect(tool.name == "perplexity_search")
        #expect(tool.args == [:])
        #expect(tool.outputSchema != nil)

        let configured = gatewayTools.perplexitySearch(.init(
            maxResults: 10,
            maxTokensPerPage: 2048,
            maxTokens: 25_000,
            country: "US",
            searchDomainFilter: ["nature.com", "-spam.net"],
            searchLanguageFilter: ["en"],
            searchRecencyFilter: .week
        ))

        guard let args = configured.args else {
            Issue.record("Expected args")
            return
        }

        #expect(args["maxResults"] == .number(10))
        #expect(args["maxTokensPerPage"] == .number(2048))
        #expect(args["maxTokens"] == .number(25_000))
        #expect(args["country"] == .string("US"))
        #expect(args["searchDomainFilter"] == .array([.string("nature.com"), .string("-spam.net")]))
        #expect(args["searchLanguageFilter"] == .array([.string("en")]))
        #expect(args["searchRecencyFilter"] == .string("week"))
    }
}

