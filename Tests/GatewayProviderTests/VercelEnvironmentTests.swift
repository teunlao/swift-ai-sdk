import Testing
@testable import GatewayProvider

@Suite("Gateway Vercel Environment")
struct VercelEnvironmentTests {
    @Test("getVercelRequestId reads x-vercel-id from TaskLocal request context")
    func requestIdFromTaskLocalContext() async throws {
        let requestId = await GatewayVercelRequestContext.$headers.withValue(
            ["x-vercel-id": "req_1234567890abcdef"]
        ) {
            await getVercelRequestId()
        }

        #expect(requestId == "req_1234567890abcdef")
    }

    @Test("getVercelRequestId is case-insensitive for header name")
    func requestIdHeaderCaseInsensitivity() async throws {
        let requestId = await GatewayVercelRequestContext.$headers.withValue(
            ["X-Vercel-Id": "req_case"]
        ) {
            await getVercelRequestId()
        }

        #expect(requestId == "req_case")
    }

    @Test("getVercelRequestId returns nil when header is missing")
    func requestIdMissingHeader() async throws {
        let requestId = await GatewayVercelRequestContext.$headers.withValue(
            ["x-other-header": "value"]
        ) {
            await getVercelRequestId()
        }

        #expect(requestId == nil)
    }
}

